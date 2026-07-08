"""
GENERACIÓN DE DATASET - SISTEMA DE GEOCERCAS INTELIGENTES
"""
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from collections import defaultdict

# ZONAS DE LA PAZ Y EL ALTO

ZONES_LA_PAZ = {
    'sopocachi': {
        'lat': -16.5095,
        'lng': -68.1285,
        'alt': 3600,
        'risk': 0.50,
        'terrain': 'residential'
    },
    'miraflores': {
        'lat': -16.4980,
        'lng': -68.1200,
        'alt': 3580,
        'risk': 0.45,
        'terrain': 'residential'
    },
    'san_jorge': {
        'lat': -16.5120,
        'lng': -68.1230,
        'alt': 3550,
        'risk': 0.35,
        'terrain': 'residential'
    },
    'centro': {
        'lat': -16.4975,
        'lng': -68.1355,
        'alt': 3640,
        'risk': 0.75,
        'terrain': 'urban'
    },
    'plaza_murillo': {
        'lat': -16.4958,
        'lng': -68.1335,
        'alt': 3640,
        'risk': 0.65,
        'terrain': 'urban'
    },
    'villa_fatima': {
        'lat': -16.4865,
        'lng': -68.1150,
        'alt': 3750,
        'risk': 0.85,
        'terrain': 'residential'
    },
    'obrajes': {
        'lat': -16.5260,
        'lng': -68.1065,
        'alt': 3350,
        'risk': 0.30,
        'terrain': 'residential'
    },
    'calacoto': {
        'lat': -16.5380,
        'lng': -68.0850,
        'alt': 3250,
        'risk': 0.25,
        'terrain': 'residential'
    },
    'san_miguel': {
        'lat': -16.5414,
        'lng': -68.0796,
        'alt': 3240,
        'risk': 0.20,
        'terrain': 'residential'
    },
    'cota_cota': {
        'lat': -16.5435,
        'lng': -68.0665,
        'alt': 3250,
        'risk': 0.30,
        'terrain': 'residential'
    },
    'achumani': {
        'lat': -16.5380,
        'lng': -68.0610,
        'alt': 3280,
        'risk': 0.30,
        'terrain': 'residential'
    },
    'cotahuma': {
        'lat': -16.5130,
        'lng': -68.1400,
        'alt': 3750,
        'risk': 0.65,
        'terrain': 'hillside'
    },
    'tembladerani': {
        'lat': -16.5120,
        'lng': -68.1450,
        'alt': 3780,
        'risk': 0.65,
        'terrain': 'hillside'
    }
}

ZONES_EL_ALTO = {
    'la_ceja': {
        'lat': -16.5036,
        'lng': -68.1627,
        'alt': 4050,
        'risk': 0.95,
        'terrain': 'urban'
    },
    'ciudad_satelite': {
        'lat': -16.5206,
        'lng': -68.1542,
        'alt': 4060,
        'risk': 0.50,
        'terrain': 'residential'
    },
    'villa_dolores': {
        'lat': -16.5136,
        'lng': -68.1568,
        'alt': 4060,
        'risk': 0.70,
        'terrain': 'residential'
    },
    'avenida_6_marzo': {
        'lat': -16.5166,
        'lng': -68.1672,
        'alt': 4050,
        'risk': 0.85,
        'terrain': 'urban'
    },
    'mercado_16_julio': {
        'lat': -16.4880,
        'lng': -68.1730,
        'alt': 4050,
        'risk': 0.90,
        'terrain': 'urban'
    },
    'villa_adela': {
        'lat': -16.5337,
        'lng': -68.1912,
        'alt': 4040,
        'risk': 0.55,
        'terrain': 'residential'
    },
    'villa_exaltacion': {
        'lat': -16.5290,
        'lng': -68.1790,
        'alt': 4000,
        'risk': 0.60,
        'terrain': 'residential'
    },
    'rio_seco': {
        'lat': -16.4898,
        'lng': -68.2096,
        'alt': 4030,
        'risk': 0.80,
        'terrain': 'periurban'
    },
    'senkata': {
        'lat': -16.5710,
        'lng': -68.1874,
        'alt': 4020,
        'risk': 0.75,
        'terrain': 'periurban'
    }
}

ALL_ZONES = {**ZONES_LA_PAZ, **ZONES_EL_ALTO}

# CONFIGURACIÓN DE SIMULACIÓN

LABEL_DISTRIBUTION = {
    0: 0.75,  # Normal
    1: 0.15,  # Anómalo
    2: 0.10,  # Crítico
}

WINDOW_DURATION_MIN = 10


def get_signal_quality_factor(terrain, altitude):
    """
    Factor de calidad de señal GNSS según topografía.
    Basado en estudios de propagación en entornos urbanos.
    """
    base_factor = 1.0
    terrain_penalties = {
        'urban_canyon': 0.7,
        'hillside': 0.8,
        'dense_urban': 0.65,
        'periurban': 0.75,
        'flat': 1.0,
        'mixed': 0.85,
    }
    base_factor *= terrain_penalties.get(terrain, 1.0)
    if altitude > 4000:
        base_factor *= 0.95
    return base_factor


def assign_user_home():
    """
    Cada usuario tiene su propio hogar.
    El hogar se asigna aleatoriamente entre zonas de bajo riesgo
    """
    residential_zones = [
        z for z, info in ALL_ZONES.items()
        if info.get('risk', 1) <= 0.6
        and info.get('terrain') not in ['industrial', 'commercial']
    ]

    if len(residential_zones) == 0:
        raise ValueError("No hay zonas válidas para asignar hogares")

    home_zone = np.random.choice(residential_zones)
    zone_info = ALL_ZONES[home_zone]

    return {
        'lat': zone_info['lat'] + np.random.normal(0, 0.0015),
        'lng': zone_info['lng'] + np.random.normal(0, 0.0015),
        'zone': home_zone,
    }


def generate_trajectory_for_user(user_id, home, target_label, duration_minutes=60):
    """
    Genera una trayectoria de 60 minutos para un usuario específico.
    La etiqueta target_label INFLUYE en la probabilidad de ciertos patrones,
    pero no los garantiza. 
    """

    zone_keys = list(ALL_ZONES.keys())
    start_zone = np.random.choice(zone_keys)
    zone_info = ALL_ZONES[start_zone]
    
    current_lat = zone_info['lat'] + np.random.normal(0, 0.001)
    current_lng = zone_info['lng'] + np.random.normal(0, 0.001)
    
    signal_factor = get_signal_quality_factor(zone_info['terrain'], zone_info['alt'])
    
    # Parámetros base de movimiento (se MODULAN según la etiqueta objetivo, pero con ruido)
    if target_label == 0:  # Normal
        speed_mean = np.random.uniform(1.0, 2.5)
        speed_std = 0.5
        dir_change_prob = 0.1
        stationary_prob = 0.05
    elif target_label == 1:  # Anómalo
        speed_mean = np.random.uniform(0.5, 4.0)  
        speed_std = 1.5
        dir_change_prob = 0.25
        stationary_prob = 0.20
    else:  # Crítico
        speed_mean = np.random.uniform(2.0, 6.0)
        speed_std = 2.5
        dir_change_prob = 0.35
        stationary_prob = 0.25
    
    points = []
    current_time = datetime(2024, 3, 15, np.random.randint(0, 24), 0)
    prev_angle = np.random.uniform(0, 2 * np.pi)
    
    # Ruido adicional para garantizar solapamiento entre clases
    noise_factor = np.random.uniform(0.7, 1.3)
    
    for i in range(duration_minutes):
        if np.random.random() < stationary_prob:
            speed = max(0, np.random.normal(0, 0.3))
            stationarity = 1.0
        else:
            speed = max(0, np.random.normal(speed_mean * noise_factor, speed_std))
            stationarity = 0.0
        
        if np.random.random() < dir_change_prob:
            angle = np.random.uniform(0, 2 * np.pi)
        else:
            angle = prev_angle + np.random.normal(0, 0.4)
        
        prev_angle = angle
        
        displacement = speed * 0.00001
        current_lat += displacement * np.sin(angle)
        current_lng += displacement * np.cos(angle)
        
        if i >= 2 and len(points) >= 2:
            prev_lat = points[-1]['latitude']
            prev_lng = points[-1]['longitude']
            prev2_lat = points[-2]['latitude']
            prev2_lng = points[-2]['longitude']
            
            v1 = (prev_lat - prev2_lat, prev_lng - prev2_lng)
            v2 = (current_lat - prev_lat, current_lng - prev_lng)
            
            dot = v1[0]*v2[0] + v1[1]*v2[1]
            mag1 = max(1e-10, (v1[0]**2 + v1[1]**2)**0.5)
            mag2 = max(1e-10, (v2[0]**2 + v2[1]**2)**0.5)
            cos_angle = max(-1, min(1, dot / (mag1 * mag2)))
            angle_diff = np.arccos(cos_angle)
            direction_change_rate = angle_diff / np.pi
        else:
            direction_change_rate = 0.0
        
        hour = current_time.hour
        hour_sin = np.sin(2 * np.pi * hour / 24)
        hour_cos = np.cos(2 * np.pi * hour / 24)
        day_of_week = current_time.weekday()
        
        distance_from_home = np.sqrt(
            (current_lat - home['lat'])**2 + (current_lng - home['lng'])**2
        ) * 111000 
        
        # Calidad de señal con ruido
        base_accuracy = 10.0
        accuracy = base_accuracy / signal_factor + np.random.normal(0, 3)
        accuracy = max(5.0, accuracy)
        
        points.append({
            'user_id': user_id,
            'timestamp': current_time.isoformat(),
            'latitude': current_lat,
            'longitude': current_lng,
            'altitude': zone_info['alt'],
            'terrain_type': zone_info['terrain'],
            'speed': speed,
            'zone_risk_level': zone_info['risk'],
            'accuracy': accuracy,
            'hour_sin': hour_sin,
            'hour_cos': hour_cos,
            'day_of_week': day_of_week,
            'distance_from_home': distance_from_home,
            'stationarity_index': stationarity,
            'direction_change_rate': direction_change_rate,
            'is_night': 1 if (hour >= 22 or hour <= 5) else 0,
            'is_rush_hour': 1 if (7 <= hour <= 9 or 17 <= hour <= 19) else 0,
            'target_label': target_label, 
            'home_lat': home['lat'],
            'home_lng': home['lng'],
        })
        
        current_time += timedelta(minutes=1)
    
    return points


def aggregate_window(points):
    """
    Agregar puntos GPS en ventanas temporales.
    El modelo debe aprender COMPORTAMIENTO, no puntos individuales.
    Cada muestra representa 10 minutos de actividad.
    """

    if len(points) < 5:
        return None
    
    df = pd.DataFrame(points)
    
    # Calcular distancia total recorrida
    total_distance = 0.0
    for i in range(1, len(df)):
        dlat = df.iloc[i]['latitude'] - df.iloc[i-1]['latitude']
        dlng = df.iloc[i]['longitude'] - df.iloc[i-1]['longitude']
        total_distance += np.sqrt(dlat**2 + dlng**2) * 111000
    
    aggregated = {
        'user_id': df['user_id'].iloc[0],
        'window_start': df['timestamp'].iloc[0],
        'window_end': df['timestamp'].iloc[-1],
        'n_points': len(df),
        
        # Velocidad
        'mean_speed': df['speed'].mean(),
        'max_speed': df['speed'].max(),
        'std_speed': df['speed'].std() if len(df) > 1 else 0.0,
        'total_distance': total_distance,
        
        # Dirección
        'mean_direction_change': df['direction_change_rate'].mean(),
        'max_direction_change': df['direction_change_rate'].max(),
        
        # Permanencia
        'stationary_ratio': df['stationarity_index'].mean(),
        
        # Distancia al hogar
        'max_distance_from_home': df['distance_from_home'].max(),
        'mean_distance_from_home': df['distance_from_home'].mean(),
        
        # Riesgo de zona
        'mean_zone_risk': df['zone_risk_level'].mean(),
        'max_zone_risk': df['zone_risk_level'].max(),
        
        # Calidad GPS
        'gps_accuracy_mean': df['accuracy'].mean(),
        'gps_accuracy_std': df['accuracy'].std() if len(df) > 1 else 0.0,
        
        # Contexto temporal
        'mean_hour_sin': df['hour_sin'].mean(),
        'mean_hour_cos': df['hour_cos'].mean(),
        'night_ratio': df['is_night'].mean(),
        'rush_hour_ratio': df['is_rush_hour'].mean(),
        
        # Altitud
        'mean_altitude': df['altitude'].mean(),
        
        # Etiqueta de la ventana
        'label': df['target_label'].iloc[0],
        
        # Home del usuario
        'home_lat': df['home_lat'].iloc[0],
        'home_lng': df['home_lng'].iloc[0],
    }
    
    return aggregated


def generate_dataset(n_users=200, windows_per_user=10):
    all_windows = []
    
    # Asignar home a cada usuario
    user_homes = {uid: assign_user_home() for uid in range(n_users)}
    
    # Contador de etiquetas para verificar distribución
    label_counts = defaultdict(int)
    
    for user_id in range(n_users):
        home = user_homes[user_id]
        
        for window_idx in range(windows_per_user):
            # Selecciona etiqueta según distribución objetivo
            target_label = np.random.choice(
                [0, 1, 2],
                p=[LABEL_DISTRIBUTION[0], LABEL_DISTRIBUTION[1], LABEL_DISTRIBUTION[2]]
            )
            
            # Trayectoria de 60 minutos
            trajectory = generate_trajectory_for_user(
                user_id, home, target_label, duration_minutes=60
            )
            
            # Ventanas de 10 minutos
            for start_idx in range(0, len(trajectory) - WINDOW_DURATION_MIN + 1, WINDOW_DURATION_MIN):
                window_points = trajectory[start_idx:start_idx + WINDOW_DURATION_MIN]
                aggregated = aggregate_window(window_points)
                
                if aggregated is not None:
                    all_windows.append(aggregated)
                    label_counts[target_label] += 1
    
    df = pd.DataFrame(all_windows)
    
    # Verificar distribución
    print("\n" + "=" * 70)
    print("DISTRIBUCIÓN DE CLASES EN EL DATASET")
    print("=" * 70)
    total = len(df)
    for label, name in [(0, 'Normal'), (1, 'Anómalo'), (2, 'Crítico')]:
        count = (df['label'] == label).sum()
        pct = count / total * 100
        target_pct = LABEL_DISTRIBUTION[label] * 100
        print(f"  {name:10s}: {count:5d} ({pct:5.1f}%) [objetivo: {target_pct:.0f}%]")
    
    return df

if __name__ == '__main__':
    print("=" * 70)
    print("GENERACIÓN DE DATASET")
    print("Ventanas temporales + Homes individuales")
    print("=" * 70)
    
    df = generate_dataset(n_users=200, windows_per_user=10)
    
    df.to_csv('training/mobility_dataset.csv', index=False)
    
    print(f"\n Dataset generado: {len(df)} ventanas temporales")
    print(f"   Usuarios únicos: {df['user_id'].nunique()}")
    print(f"   Features por muestra: {len(df.columns) - 5}")
    print(f"\n Archivo guardado: training/mobility_dataset.csv")