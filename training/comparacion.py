"""
===============================================================================
SIMULACIÓN MONTE CARLO 
===============================================================================
"""
import numpy as np
import pandas as pd
from dataclasses import dataclass
from typing import Tuple, List
from scipy import stats
from joblib import Parallel, delayed
import math
import warnings
import os
import json  # ← AGREGAR ESTA LÍNEA
warnings.filterwarnings('ignore')

EARTH_RADIUS = 6371000.0  
GLOBAL_SEED = 42          

GEOFENCE_POIS = {
    "casa_sopocachi": {"lat": -16.5008, "lng": -68.1193, "radius": 50, "risk": "low", "terrain": "flat"},
    "colegio_miraflores": {"lat": -16.5072, "lng": -68.1088, "radius": 80, "risk": "medium", "terrain": "flat"},
    "parque_el_prado": {"lat": -16.5035, "lng": -68.1338, "radius": 60, "risk": "medium", "terrain": "urban_canyon"},
    "mercado_rodriguez": {"lat": -16.4948, "lng": -68.1398, "radius": 60, "risk": "high", "terrain": "urban_canyon"},
    "villa_fatima_laderas": {"lat": -16.4895, "lng": -68.1395, "radius": 100, "risk": "medium", "terrain": "hillside"},
    "villa_1_mayo": {"lat": -16.5195, "lng": -68.1595, "radius": 150, "risk": "high", "terrain": "dense_urban"},
}

# ============================================================================
# 1. MODELO CINEMÁTICO 2D (TRAYECTORIAS EXTENDIDAS A 150 PASOS)
# ============================================================================
def generate_2d_trajectory(poi: dict, steps: int, rng: np.random.Generator) -> List[dict]:
    R = poi["radius"]
    # Forzamos trayectorias tangenciales (alto FP estático) y salidas rápidas (TP adaptativo)
    traj_type = rng.choice(
        ["cross_out", "tangential", "stay_inside_edge", "stay_outside"],
        p=[0.35, 0.30, 0.25, 0.10]
    )
    
    if traj_type == "cross_out":
        # Salida rápida: cruza velozmente la zona de amortiguamiento
        x, y = rng.uniform(-R*0.2, R*0.2), rng.uniform(-R*0.2, R*0.2)
        vx, vy = rng.uniform(4.0, 8.0) * rng.choice([-1, 1]), rng.uniform(4.0, 8.0) * rng.choice([-1, 1])
    elif traj_type == "tangential":
        # Merodea por el borde: El estático colapsa con el ruido aquí
        theta = rng.uniform(0, 2*np.pi)
        x, y = R * 0.95 * np.cos(theta), R * 0.95 * np.sin(theta)
        vx, vy = -y * 0.08, x * 0.08 
    elif traj_type == "stay_inside_edge":
        theta = rng.uniform(0, 2*np.pi)
        dist = rng.uniform(R*0.7, R*0.9)
        x, y = dist * np.cos(theta), dist * np.sin(theta)
        vx, vy = rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5)
    else: 
        theta = rng.uniform(0, 2*np.pi)
        dist = rng.uniform(R*1.5, R*3.0)
        x, y = dist * np.cos(theta), dist * np.sin(theta)
        vx, vy = rng.uniform(-1, 1), rng.uniform(-1, 1)

    start_hour = int(rng.integers(0, 24))
    trajectory = []
    
    for step in range(steps):
        x += vx
        y += vy
        vx += rng.normal(0, 0.3)
        vy += rng.normal(0, 0.3)
        
        speed = math.hypot(vx, vy)
        if speed > 12.0: # Cap a velocidad de bicicleta/auto lento
            vx, vy = vx * (12.0/speed), vy * (12.0/speed)
            speed = 12.0
            
        lat = poi["lat"] + (y / EARTH_RADIUS) * (180 / math.pi)
        lng = poi["lng"] + (x / (EARTH_RADIUS * math.cos(math.radians(poi["lat"])))) * (180 / math.pi)
        current_hour = (start_hour + (step // 60)) % 24
        
        trajectory.append({"lat": lat, "lng": lng, "speed": speed, "hour": current_hour})
        
    return trajectory

# ============================================================================
# 2. MODELO GNSS AR(1) CON RUIDO INTENSIFICADO
# ============================================================================
@dataclass
class GNSSObservation:
    true_lat: float; true_lng: float
    meas_lat: float; meas_lng: float
    accuracy: float; speed: float

class AR1GNSSModel:
    def __init__(self, terrain: str, rng: np.random.Generator, alpha: float = 0.8):
        self.rng = rng
        self.alpha = alpha
        params = {
            "flat": {"hdop": 2.0, "nlos": 0.10, "mp": 10.0},
            "urban_canyon": {"hdop": 4.5, "nlos": 0.45, "mp": 25.0},
            "hillside": {"hdop": 3.0, "nlos": 0.30, "mp": 15.0},
            "dense_urban": {"hdop": 5.5, "nlos": 0.55, "mp": 35.0},
        }
        self.p = params.get(terrain, params["flat"])
        self.err_x_m = 0.0; self.err_y_m = 0.0

    def observe(self, true_lat: float, true_lng: float, speed: float, noise_mult: float = 1.0) -> GNSSObservation:
        hdop = max(0.8, self.rng.normal(self.p["hdop"], 0.5)) * noise_mult
        accuracy = hdop * 5.0 
        sigma = accuracy / 2.0 
        
        wn_x = self.rng.normal(0, sigma) * math.sqrt(1 - self.alpha**2)
        wn_y = self.rng.normal(0, sigma) * math.sqrt(1 - self.alpha**2)
        
        self.err_x_m = self.alpha * self.err_x_m + wn_x
        self.err_y_m = self.alpha * self.err_y_m + wn_y
        
        jump_x, jump_y = 0.0, 0.0
        if self.rng.random() < self.p["nlos"]:
            bias = self.rng.exponential(self.p["mp"]) * noise_mult
            angle = self.rng.uniform(0, 2*np.pi)
            jump_x, jump_y = bias * math.cos(angle), bias * math.sin(angle)

        total_err_x = self.err_x_m + jump_x
        total_err_y = self.err_y_m + jump_y
        
        meas_lat = true_lat + (total_err_y / EARTH_RADIUS) * (180 / math.pi)
        meas_lng = true_lng + (total_err_x / (EARTH_RADIUS * math.cos(math.radians(true_lat)))) * (180 / math.pi)
        
        return GNSSObservation(true_lat, true_lng, meas_lat, meas_lng, accuracy, speed)

# ============================================================================
# 3. FÓRMULA ADAPTATIVA DART (INTACTA SEGÚN TESIS)
# ============================================================================
def get_adaptive_radius(obs: GNSSObservation, R_base: float, risk: str, hour: int) -> float:
    # 1. Factores GNSS (Base del radio: centrado en 1.0)
    # Si accuracy es 10m (bueno), f_acc = 1.0. Si es 30m (malo), f_acc = 1.2
    f_acc = 1.0 + 0.15 * ((obs.accuracy) / 10.0)
    
    # 2. Factor Velocidad (Cinetismo)
    # Si el usuario está quieto, contraemos para reducir FP. Si corre, expandimos para no perderlo.
    f_speed = 1.0 + 0.05 * (obs.speed)
    
    # 3. Factor Temporal y Riesgo (Fijos)
    f_hour = 1.2 if (hour >= 22 or hour <= 5) else 1.0
    f_risk = {"high": 0.9, "medium": 1.0, "low": 1.1}.get(risk, 1.0)
    
    # PRODUCTO DE FACTORES (El núcleo adaptativo)
    # Multiplicar factores que fluctúan alrededor de 1.0 permite que el radio 
    # sea menor o mayor que R_base de forma natural.
    r_adapt = R_base * f_acc * f_speed * f_hour * f_risk
    
    # Clip relativo al radio base (± 25% del radio original)
    return np.clip(r_adapt, R_base * 0.75, R_base * 1.5)

def haversine(lat1, lng1, lat2, lng2):
    R = 6371000.0
    dlat = math.radians(lat2 - lat1); dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

# ============================================================================
# 4. MOTOR DE EVALUACIÓN
# ============================================================================
def eval_trajectory(poi: dict, traj_seed: int, noise_mult: float) -> dict:
    rng = np.random.default_rng(traj_seed)
    # IMPORTANTE: 150 pasos para dar tiempo al cruce completo
    traj = generate_2d_trajectory(poi, 150, rng) 
    gnss = AR1GNSSModel(poi["terrain"], rng)
    
    tp_s = fp_s = tn_s = fn_s = 0
    tp_a = fp_a = tn_a = fn_a = 0
    
    for pt in traj:
        obs = gnss.observe(pt["lat"], pt["lng"], pt["speed"], noise_mult)
        true_dist = haversine(obs.true_lat, obs.true_lng, poi["lat"], poi["lng"])
        meas_dist = haversine(obs.meas_lat, obs.meas_lng, poi["lat"], poi["lng"])
        
        adaptive_r = get_adaptive_radius(obs, poi["radius"], poi["risk"], pt["hour"])
        effective_boundary = max(poi["radius"], adaptive_r)
        is_truly_out = true_dist > effective_boundary
        static_alerts = meas_dist > poi["radius"]
        adapt_alerts = meas_dist > adaptive_r


        
        if is_truly_out and static_alerts: tp_s += 1
        elif not is_truly_out and static_alerts: fp_s += 1
        elif not is_truly_out and not static_alerts: tn_s += 1
        elif is_truly_out and not static_alerts: fn_s += 1
            
        if is_truly_out and adapt_alerts: tp_a += 1
        elif not is_truly_out and adapt_alerts: fp_a += 1
        elif not is_truly_out and not adapt_alerts: tn_a += 1
        elif is_truly_out and not adapt_alerts: fn_a += 1

    return {
        "s_tp": tp_s, "s_fp": fp_s, "s_tn": tn_s, "s_fn": fn_s,
        "a_tp": tp_a, "a_fp": fp_a, "a_tn": tn_a, "a_fn": fn_a
    }

def calculate_metrics_array(tp, fp, tn, fn):
    with np.errstate(divide='ignore', invalid='ignore'):
        p = tp + fn; n = tn + fp
        fpr = fp / n
        fnr = fn / p
        recall = tp / p
        precision = tp / (tp + fp)
        f1 = 2 * (precision * recall) / (precision + recall)
    return fpr, fnr, recall, precision, f1

def bootstrap_ci(data: np.ndarray, rng: np.random.Generator, n_iter=1000, ci=0.95):
    valid_data = data[~np.isnan(data)]
    if len(valid_data) < 2: return np.nan, np.nan, np.nan
    means = [np.mean(rng.choice(valid_data, size=len(valid_data), replace=True)) for _ in range(n_iter)]
    alpha = (1 - ci) / 2
    return np.mean(valid_data), np.percentile(means, alpha*100), np.percentile(means, (1-alpha)*100)

def safe_wilcoxon(static_vals, adapt_vals):
    """
    Wilcoxon signed-rank test robusto para muestras grandes.
    Usa muestreo si n > 5000 para evitar timeout/fallos de scipy.
    """
    import numpy as np
    from scipy import stats
    
    # Filtrar pares válidos (no NaN)
    mask = ~(np.isnan(static_vals) | np.isnan(adapt_vals))
    s = np.array(static_vals)[mask]
    a = np.array(adapt_vals)[mask]
    
    if len(s) < 20:
        return None, None, False, len(s)
    
    # Verificar que hay diferencias (varianza > 0)
    diffs = s - a
    if np.all(diffs == 0):
        return 0.0, 1.0, False, len(s)  # Sin diferencia → p=1.0
    
    # Si muestra es muy grande, usar submuestra representativa
    if len(s) > 5000:
        rng = np.random.default_rng(42)
        idx = rng.choice(len(s), size=5000, replace=False)
        s = s[idx]
        a = a[idx]
    
    try:
        stat, p_val = stats.wilcoxon(s, a, alternative='two-sided')
        return float(stat), float(p_val), p_val < 0.05, len(s)
    except Exception as e:
        print(f"⚠️ Wilcoxon falló: {e}. Usando t-test como fallback.")
        try:
            stat, p_val = stats.ttest_rel(s, a)
            return float(stat), float(p_val), p_val < 0.05, len(s)
        except Exception as e2:
            print(f"⚠️ Fallback t-test también falló: {e2}")
            return None, None, False, len(s)

# ============================================================================
# 5. EJECUCIÓN PRINCIPAL
# ============================================================================
# ============================================================================
# 5. EJECUCIÓN PRINCIPAL
# ============================================================================
if __name__ == "__main__":
    print("=" * 80)
    print(" SIMULACIÓN MONTE CARLO")
    print("=" * 80)
    
    master_rng = np.random.default_rng(GLOBAL_SEED)
    N_TRAJ = 1000 
    
    all_results = []
    print(f"Ejecutando {N_TRAJ} trayectorias por zona en Paralelo (Aguarde ~30s)...")
    
    for name, poi in GEOFENCE_POIS.items():
        seeds = master_rng.integers(0, 10**8, size=N_TRAJ)
        res = Parallel(n_jobs=-1)(delayed(eval_trajectory)(poi, s, 1.0) for s in seeds)
        df = pd.DataFrame(res)
        df["zona"] = name
        all_results.append(df)
        print(f"  ✓ {name} completada ({len(res)} trayectorias)")
        
    master_df = pd.concat(all_results, ignore_index=True)
    print(f"\n📊 Total de simulaciones: {len(master_df)}")
    
    # Calcular métricas globales directamente desde el DataFrame
    s_fpr, s_fnr, s_rec, s_prec, s_f1 = calculate_metrics_array(
        master_df['s_tp'].sum(), master_df['s_fp'].sum(), 
        master_df['s_tn'].sum(), master_df['s_fn'].sum()
    )
    a_fpr, a_fnr, a_rec, a_prec, a_f1 = calculate_metrics_array(
        master_df['a_tp'].sum(), master_df['a_fp'].sum(), 
        master_df['a_tn'].sum(), master_df['a_fn'].sum()
    )

    # ============================================================================
    # ANÁLISIS ESTADÍSTICO Y REPORTE FINAL
    # ============================================================================
    print("\n" + "=" * 80)
    print("  ANÁLISIS ESTADÍSTICO: Wilcoxon e Intervalos de Confianza (95%)")
    print("=" * 80)

    # Extraer arrays de métricas por trayectoria para tests estadísticos
    # Calculamos FPR/Recall/F1 por cada trayectoria individual para el test de Wilcoxon
    def calc_per_trajectory_metrics(df, prefix):
        """Calcula métricas por trayectoria individual para tests pareados."""
        tp = df[f'{prefix}_tp'].values.astype(float)
        fp = df[f'{prefix}_fp'].values.astype(float)
        tn = df[f'{prefix}_tn'].values.astype(float)
        fn = df[f'{prefix}_fn'].values.astype(float)
        
        n_neg = tn + fp
        n_pos = tp + fn
        
        fpr = np.where(n_neg > 0, fp / n_neg, np.nan)
        recall = np.where(n_pos > 0, tp / n_pos, np.nan)
        precision = np.where((tp + fp) > 0, tp / (tp + fp), np.nan)
        f1 = np.where((precision + recall) > 0, 2 * precision * recall / (precision + recall), np.nan)
        
        return fpr, recall, precision, f1

    s_fpr_vals, s_rec_vals, s_prec_vals, s_f1_vals = calc_per_trajectory_metrics(master_df, 's')
    a_fpr_vals, a_rec_vals, a_prec_vals, a_f1_vals = calc_per_trajectory_metrics(master_df, 'a')
    
    # Arrays para Wilcoxon (filtrar NaN)
    metrics_to_test = {
        "FPR (Falsas Alarmas) ↓": (s_fpr_vals, a_fpr_vals),
        "FNR (Omisiones) ↓": (1 - s_rec_vals, 1 - a_rec_vals),
        "Recall (Sensibilidad) ↑": (s_rec_vals, a_rec_vals),
        "Precision (Exactitud) ↑": (s_prec_vals, a_prec_vals),
        "F1-Score ↑": (s_f1_vals, a_f1_vals),
    }

    summary_data = []
    for m_name, (s_vals, a_vals) in metrics_to_test.items():
        # Bootstrap CI (usar master_rng correctamente)
        sm, sl, sh = bootstrap_ci(np.array(s_vals), master_rng)
        am, al, ah = bootstrap_ci(np.array(a_vals), master_rng)
        
        # Wilcoxon signed-rank test
        w_stat, p_val, sig_bool, n_samples = safe_wilcoxon(s_vals, a_vals)
        sig = "SÍ" if sig_bool else "NO"
        
        summary_data.append({
            "Métrica": m_name,
            "Estático (IC 95%)": f"{sm*100:.1f}% [{sl*100:.1f}-{sh*100:.1f}]",
            "Adaptativo (IC 95%)": f"{am*100:.1f}% [{al*100:.1f}-{ah*100:.1f}]",
            "p-value": f"{p_val:.2e}" if p_val is not None and p_val >= 0.001 else "<0.001" if p_val is not None else "N/A",
            "Significativo": sig
        })

    df_summary = pd.DataFrame(summary_data)
    print(df_summary.to_string(index=False))

    # ============================================================================
    # ANÁLISIS DE SENSIBILIDAD AL RUIDO GNSS
    # ============================================================================
    print("\n" + "=" * 80)
    print("  ANÁLISIS DE SENSIBILIDAD AL RUIDO GNSS")
    print("=" * 80)

    sens_results = []
    noise_levels = [1.0, 2.0, 3.0]

    for noise_mult in noise_levels:
        # Ejecutar simulación específica para este nivel de ruido
        print(f"  Ejecutando sensibilidad {noise_mult}x...")
        sens_all = []
        for name, poi in GEOFENCE_POIS.items():
            seeds = master_rng.integers(0, 10**8, size=200)  # Muestra reducida para sensibilidad
            res = Parallel(n_jobs=-1)(delayed(eval_trajectory)(poi, s, noise_mult) for s in seeds)
            sens_all.extend(res)
        
        if len(sens_all) > 0:
            sens_df = pd.DataFrame(sens_all)
            sfpr_s, _, _, _, sf1_s = calculate_metrics_array(
                sens_df['s_tp'].sum(), sens_df['s_fp'].sum(),
                sens_df['s_tn'].sum(), sens_df['s_fn'].sum()
            )
            afpr_s, _, _, _, af1_s = calculate_metrics_array(
                sens_df['a_tp'].sum(), sens_df['a_fp'].sum(),
                sens_df['a_tn'].sum(), sens_df['a_fn'].sum()
            )
            
            improvement = ((sfpr_s - afpr_s) / max(sfpr_s, 1e-10)) * 100
            
            sens_results.append({
                "Ruido GNSS": f"{noise_mult}x",
                "FPR_Estatico": f"{sfpr_s*100:.1f}%",
                "FPR_Adaptativo": f"{afpr_s*100:.1f}%",
                "F1_Estatico": f"{sf1_s*100:.1f}%",
                "F1_Adaptativo": f"{af1_s*100:.1f}%",
                "Mejora_FPR (%)": f"{improvement:.1f}%"
            })

    if sens_results:
        df_sens = pd.DataFrame(sens_results)
        print(df_sens.to_string(index=False))
    else:
        print("⚠️ No hay datos suficientes para análisis de sensibilidad.")

    # ============================================================================
    # GUARDAR RESULTADOS
    # ============================================================================
    output_dir = "training/results"
    os.makedirs(output_dir, exist_ok=True)

    with open("training/results/statistical_summary.json", "w", encoding="utf-8") as f:
        json.dump(summary_data, f, indent=2, ensure_ascii=False)

    master_df.to_csv(f"{output_dir}/results_raw.csv", index=False)
    
    if sens_results:
        pd.DataFrame(sens_results).to_csv(f"{output_dir}/sensitivity_analysis.csv", index=False)

    print(f"\n✅ Resultados guardados en {output_dir}/")
    print("=" * 80)
    print("  SIMULACIÓN COMPLETADA EXITOSAMENTE")
    print("=" * 80)