import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

class GeofenceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> createGeofence({
    required String objectiveId,
    required String name,
    required String type,
    required String riskLevel,
    GeoPoint? center,
    double? radius,
    List<Map<String, double>>? vertices,
  }) async {
    final observerId = _auth.currentUser?.uid;
    if (observerId == null) throw Exception('Usuario no autenticado');

    GeoPoint? calculatedCenter = center;
    double? calculatedRadius = radius;
    double? calculatedArea;

    if (type == 'polygon' && vertices != null && vertices.length >= 3) {
      final centroid = _calculateCentroid(vertices);
      calculatedCenter = GeoPoint(centroid.latitude, centroid.longitude);
      
      //  Calcular área del polígono
      calculatedArea = _calculateArea(vertices);
      
      //  Calcular radio equivalente
      calculatedRadius = sqrt(calculatedArea / pi);
    }

    await _firestore.collection('geofences').add({
      'objective_id': objectiveId,
      'created_by': observerId,
      'name': name,
      'type': type,
      'risk_level': riskLevel,
      'center': calculatedCenter,
      'radius': calculatedRadius,
      'area': calculatedArea,
      'vertices': vertices,
      'is_active': true,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGeofence({
    required String geofenceId,
    String? name,
    String? riskLevel,
    List<Map<String, double>>? vertices,
    double? radius,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (name != null) updates['name'] = name;
    if (riskLevel != null) updates['risk_level'] = riskLevel;
    if (isActive != null) updates['is_active'] = isActive;
    
    if (vertices != null) {
      updates['vertices'] = vertices;
      if (vertices.length >= 3) {
        final centroid = _calculateCentroid(vertices);
        updates['center'] = GeoPoint(centroid.latitude, centroid.longitude);
        final area = _calculateArea(vertices);
        updates['area'] = area;
        updates['radius'] = sqrt(area / pi);
      }
    }
    if (radius != null) updates['radius'] = radius;

    await _firestore.collection('geofences').doc(geofenceId).update(updates);
  }

  Future<void> deleteGeofence(String geofenceId) async {
    await _firestore.collection('geofences').doc(geofenceId).update({
      'is_active': false,
      'deleted_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> getActiveGeofences(String objectiveId) {
    return _firestore
        .collection('geofences')
        .where('objective_id', isEqualTo: objectiveId)
        .where('is_active', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  ///  Calcula el área del polígono usando la fórmula de Gauss
  static double _calculateArea(List<Map<String, double>> vertices) {
    if (vertices.length < 3) return 0.0;
    
    double area = 0.0;
    final n = vertices.length;
    
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final xi = vertices[i]['lat']!;
      final yi = vertices[i]['lng']!;
      final xj = vertices[j]['lat']!;
      final yj = vertices[j]['lng']!;
      area += (xi * yj - xj * yi);
    }
    
    // El área está en grados², convertir a metros² aproximado
    // 1 grado de latitud ≈ 111,320 metros
    // 1 grado de longitud ≈ 111,320 * cos(lat) metros
    // Para simplificar, usamos un factor promedio
    final latPromedio = vertices.map((v) => v['lat']!).reduce((a, b) => a + b) / n;
    final factorConversion = 111320.0 * 111320.0 * cos(_toRad(latPromedio));
    
    return (area.abs() / 2.0) * factorConversion;
  }
  static LatLng _calculateCentroid(List<Map<String, double>> vertices) {
    if (vertices.length < 3) {
      final avgLat = vertices.map((v) => v['lat']!).reduce((a, b) => a + b) / vertices.length;
      final avgLng = vertices.map((v) => v['lng']!).reduce((a, b) => a + b) / vertices.length;
      return LatLng(avgLat, avgLng);
    }

    double signedArea = 0.0;
    double cx = 0.0;
    double cy = 0.0;
    final n = vertices.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final xi = vertices[i]['lat']!;
      final yi = vertices[i]['lng']!;
      final xj = vertices[j]['lat']!;
      final yj = vertices[j]['lng']!;
      
      final cross = xi * yj - xj * yi;
      signedArea += cross;
      cx += (xi + xj) * cross;
      cy += (yi + yj) * cross;
    }

    signedArea /= 2.0;
    
    if (signedArea.abs() < 1e-10) {
      final avgLat = vertices.map((v) => v['lat']!).reduce((a, b) => a + b) / n;
      final avgLng = vertices.map((v) => v['lng']!).reduce((a, b) => a + b) / n;
      return LatLng(avgLat, avgLng);
    }
    
    cx /= (6.0 * signedArea);
    cy /= (6.0 * signedArea);

    return LatLng(cx, cy);
  }

  /// Algoritmo Ray-Casting
  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final bool intersect = ((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Distancia Haversine
  static double calculateDistance(LatLng p1, LatLng p2) {
    const R = 6371000;
    final dLat = _toRad(p2.latitude - p1.latitude);
    final dLng = _toRad(p2.longitude - p1.longitude);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(p1.latitude)) * cos(_toRad(p2.latitude)) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * (pi / 180);
}