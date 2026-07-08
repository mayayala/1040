"""
ENTRENAMIENTO DE ÁRBOL DE DECISIÓN 
"""
import pandas as pd
import numpy as np
from sklearn.tree import DecisionTreeClassifier, export_text, plot_tree
from sklearn.model_selection import GroupShuffleSplit, train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (
    classification_report, confusion_matrix,
    precision_recall_curve, average_precision_score,
    roc_curve, auc
)
from imblearn.over_sampling import SMOTE
import json
import os
import matplotlib.pyplot as plt
import matplotlib
import seaborn as sns
from collections import Counter

matplotlib.rcParams['font.sans-serif'] = ['Segoe UI', 'Arial', 'DejaVu Sans']
matplotlib.rcParams['axes.unicode_minus'] = False
plt.style.use('seaborn-v0_8-whitegrid')

PLOTS_DIR = 'training/plots'
os.makedirs(PLOTS_DIR, exist_ok=True)
os.makedirs('assets/ml', exist_ok=True)

FEATURES = [
    'mean_speed', 'max_speed', 'std_speed', 'total_distance',
    'mean_direction_change', 'max_direction_change',
    'stationary_ratio',
    'max_distance_from_home', 'mean_distance_from_home',
    'mean_zone_risk', 'max_zone_risk',
    'gps_accuracy_mean', 'gps_accuracy_std',
    'mean_hour_sin', 'mean_hour_cos',
    'night_ratio', 'rush_hour_ratio',
    'mean_altitude',
]

CLASS_NAMES = ['Normal', 'Anómalo', 'Crítico']
CLASS_COLORS = ['#2ecc71', '#f39c12', '#e74c3c']

print("=" * 70)
print("  ENTRENAMIENTO DE ÁRBOL DE DECISIÓN")
print("=" * 70)

# CARGAR DATASET
print("\n [PASO 1] Cargando dataset...")
df = pd.read_csv('training/mobility_dataset.csv')
print(f"   Total de muestras: {len(df)}")
print(f"   Usuarios únicos: {df['user_id'].nunique()}")
print(f"   Features: {len(FEATURES)}")

# SPLIT POR USUARIO
print("\n [PASO 2] Split por usuario ...")

X = df[FEATURES].values
y = df['label'].values
users = df['user_id'].values

# 70% train, 15% val, 15% test - POR USUARIO
gss = GroupShuffleSplit(n_splits=1, test_size=0.30, random_state=42)
train_idx, temp_idx = next(gss.split(X, y, groups=users))

# Dividir temp en val y test (50/50)
gss2 = GroupShuffleSplit(n_splits=1, test_size=0.50, random_state=42)
val_idx, test_idx = next(gss2.split(X[temp_idx], y[temp_idx], groups=users[temp_idx]))

val_idx = temp_idx[val_idx]
test_idx = temp_idx[test_idx]

X_train, y_train, users_train = X[train_idx], y[train_idx], users[train_idx]
X_val, y_val, users_val = X[val_idx], y[val_idx], users[val_idx]
X_test, y_test, users_test = X[test_idx], y[test_idx], users[test_idx]

train_users = set(users_train)
val_users = set(users_val)
test_users = set(users_test)

print(f"   Train: {len(X_train)} muestras, {len(train_users)} usuarios")
print(f"   Val:   {len(X_val)} muestras, {len(val_users)} usuarios")
print(f"   Test:  {len(X_test)} muestras, {len(test_users)} usuarios")

overlap_tv = train_users & val_users
overlap_tt = train_users & test_users
overlap_vt = val_users & test_users

if overlap_tv or overlap_tt or overlap_vt:
    print(" ERROR: Existe leakage por usuario!")
    if overlap_tv: print(f"      Train-Val: {len(overlap_tv)} usuarios")
    if overlap_tt: print(f"      Train-Test: {len(overlap_tt)} usuarios")
    if overlap_vt: print(f"      Val-Test: {len(overlap_vt)} usuarios")
else:
    print(" Sin leakage por usuario (verificado)")

# Distribución de clases por split
print("\n   Distribución de clases:")
for split_name, y_split in [('Train', y_train), ('Val', y_val), ('Test', y_test)]:
    counts = Counter(y_split)
    total = len(y_split)
    dist = ", ".join([f"{CLASS_NAMES[i]}={counts.get(i,0)} ({counts.get(i,0)/total*100:.1f}%)" for i in range(3)])
    print(f"      {split_name:5s}: {dist}")

# NORMALIZACIÓN (SCALER SOLO EN TRAIN)

print("\n [PASO 3] Normalización...")

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)  
X_val_scaled = scaler.transform(X_val)         
X_test_scaled = scaler.transform(X_test)       

print("    Scaler ajustado únicamente con datos de entrenamiento")

# SMOTE MULTICLASE

print("\n⚖️  [PASO 4] SMOTE multiclase ...")

counter_before = Counter(y_train)
print(f"   Antes: {dict(counter_before)}")

min_class_count = min(counter_before.values())
if min_class_count < 50:
    print("     Clase minoritaria con < 50 muestras, SMOTE podría no ser efectivo")

smote = SMOTE(random_state=42, k_neighbors=min(5, min_class_count - 1))
X_train_balanced, y_train_balanced = smote.fit_resample(X_train_scaled, y_train)

counter_after = Counter(y_train_balanced)
print(f"   Después: {dict(counter_after)}")

print("    Val y Test preservan distribución real (sin SMOTE)")

# ENTRENAMIENTO DEL ÁRBOL

print("\n [PASO 5] Entrenando árbol de decisión...")

tree = DecisionTreeClassifier(
    max_depth=3,  
    min_samples_leaf=20,      
    min_samples_split=40,     
    min_impurity_decrease=0.01,
    class_weight='balanced',  
    criterion='gini',
    random_state=42,
)

tree.fit(X_train_balanced, y_train_balanced)

print(f"    Árbol entrenado")
print(f"   Profundidad: {tree.get_depth()}")
print(f"   Nodos hoja: {tree.get_n_leaves()}")
print(f"   Nodos totales: {tree.tree_.node_count}")

# EVALUACIÓN EN LOS TRES CONJUNTOS

print("\n [PASO 6] Evaluación en Train, Val y Test...")

def evaluate_model(model, X, y, split_name):
    """Evalúa modelo y retorna métricas completas."""
    y_pred = model.predict(X)
    y_proba = model.predict_proba(X) if hasattr(model, 'predict_proba') else None
    
    cm = confusion_matrix(y, y_pred, labels=[0, 1, 2])
    report = classification_report(y, y_pred, target_names=CLASS_NAMES, digits=3, output_dict=True)
    
    accuracy = np.trace(cm) / cm.sum()
    
    metrics = {}
    for i, class_name in enumerate(CLASS_NAMES):
        tp = cm[i, i]
        fp = cm[:, i].sum() - tp
        fn = cm[i, :].sum() - tp
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
        fp_rate = fp / (fp + tp) if (fp + tp) > 0 else 0
        metrics[class_name] = {
            'precision': precision,
            'recall': recall,
            'f1': f1,
            'fp_count': fp,
            'fn_count': fn,
            'fp_rate': fp_rate,
        }
    
    macro_f1 = np.mean([metrics[c]['f1'] for c in CLASS_NAMES])
    
    print(f"\n   {'='*60}")
    print(f"   {split_name}")
    print(f"   {'='*60}")
    print(f"   Accuracy: {accuracy:.3f}")
    print(f"   Macro F1: {macro_f1:.3f}")
    print(f"\n   Matriz de confusión:")
    print(f"            Pred:Norm  Pred:Anóm  Pred:Crít")
    for i, name in enumerate(CLASS_NAMES):
        print(f"   Real:{name:5s}  {cm[i,0]:6d}   {cm[i,1]:6d}   {cm[i,2]:6d}")
    
    print(f"\n   Métricas por clase:")
    for class_name in CLASS_NAMES:
        m = metrics[class_name]
        print(f"      {class_name:10s}: P={m['precision']:.3f}  R={m['recall']:.3f}  F1={m['f1']:.3f}  FP={m['fp_count']}  FN={m['fn_count']}")
    
    return {
        'accuracy': accuracy,
        'macro_f1': macro_f1,
        'metrics': metrics,
        'cm': cm,
        'y_pred': y_pred,
        'y_proba': y_proba,
    }

results_train = evaluate_model(tree, X_train_balanced, y_train_balanced, 'TRAIN (balanceado)')
results_val = evaluate_model(tree, X_val_scaled, y_val, 'VALIDATION')
results_test = evaluate_model(tree, X_test_scaled, y_test, 'TEST')

print("\n" + "=" * 70)
print("VERIFICACIÓN DE OBJETIVOS MÍNIMOS (Test set)")
print("=" * 70)

test_metrics = results_test['metrics']
objectives = {
    'Recall Crítico >= 80%': test_metrics['Crítico']['recall'] >= 0.80,
    'Recall Anómalo >= 80%': test_metrics['Anómalo']['recall'] >= 0.80,
    'Recall Normal >= 80%': test_metrics['Normal']['recall'] >= 0.80,
    'Precision Crítico >= 75%': test_metrics['Crítico']['precision'] >= 0.75,
    'Precision Anómalo >= 75%': test_metrics['Anómalo']['precision'] >= 0.75,
    'Precision Normal >= 75%': test_metrics['Normal']['precision'] >= 0.75,
    'Macro F1 >= 75%': results_test['macro_f1'] >= 0.75,
}

all_passed = True
for objective, passed in objectives.items():
    status = "" if passed else ""
    print(f"   {status} {objective}")
    if not passed:
        all_passed = False

if all_passed:
    print("\n    Todos los objetivos mínimos alcanzados")
else:
    print("\n    Algunos objetivos no alcanzados")

# ANÁLISIS DE FALSOS POSITIVOS/NEGATIVOS

print("\n" + "=" * 70)
print("ANÁLISIS DE FALSOS POSITIVOS Y NEGATIVOS ")
print("=" * 70)

cm_test = results_test['cm']

print("\nFalsos positivos (predichos como X pero son Y):")
for i, pred_class in enumerate(CLASS_NAMES):
    fp_count = cm_test[:, i].sum() - cm_test[i, i]
    if fp_count > 0:
        print(f"   Predicho como {pred_class}: {fp_count} falsos positivos")
        for j, real_class in enumerate(CLASS_NAMES):
            if i != j and cm_test[j, i] > 0:
                print(f"      - {cm_test[j, i]} eran realmente {real_class}")

print("\nFalsos negativos (eran X pero predichos como Y):")
for i, real_class in enumerate(CLASS_NAMES):
    fn_count = cm_test[i, :].sum() - cm_test[i, i]
    if fn_count > 0:
        print(f"   Eran {real_class}: {fn_count} falsos negativos")
        for j, pred_class in enumerate(CLASS_NAMES):
            if i != j and cm_test[i, j] > 0:
                print(f"      - {cm_test[i, j]} predichos como {pred_class}")

false_critical_from_normal = cm_test[0, 2]
total_normals = cm_test[0].sum()
print(f"\n  CRÍTICO: {false_critical_from_normal} eventos Normales clasificados como Críticos")
print(f"   Tasa: {false_critical_from_normal/max(1,total_normals)*100:.2f}% de los normales")
print(f"   Impacto: fatiga de alertas, pérdida de confianza del usuario")

print("\n" + "=" * 70)
print("IMPORTANCIA DE FEATURES")
print("=" * 70)

importances = tree.feature_importances_
feature_importance = sorted(zip(FEATURES, importances), key=lambda x: x[1], reverse=True)

print("\nRanking de features por importancia (Gini):")
for i, (feature, imp) in enumerate(feature_importance, 1):
    bar = "█" * int(imp * 50)
    print(f"   {i:2d}. {feature:25s} {imp:.4f} {bar}")

print("\n [PASO 10] Generando gráficas ...")

# Gráfica 1: Distribución de clases por split
fig, axes = plt.subplots(1, 3, figsize=(18, 5))
for ax, (name, y_split) in zip(axes, [('Train', y_train), ('Validation', y_val), ('Test', y_test)]):
    counts = [Counter(y_split).get(i, 0) for i in range(3)]
    bars = ax.bar(CLASS_NAMES, counts, color=CLASS_COLORS, edgecolor='black', linewidth=1.2)
    ax.set_title(f'Distribución {name}', fontsize=12, fontweight='bold')
    ax.set_ylabel('Número de muestras')
    for bar, count in zip(bars, counts):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(counts)*0.01,
                f'{count}\n({count/sum(counts)*100:.1f}%)', ha='center', fontweight='bold')
plt.suptitle('Distribución de Clases por Conjunto', fontsize=14, fontweight='bold', y=1.02)
plt.tight_layout()
plt.savefig(f'{PLOTS_DIR}/01_class_distribution.png', dpi=300, bbox_inches='tight')
plt.close()

# Gráfica 2: Matriz de confusión Test
fig, ax = plt.subplots(figsize=(9, 7))
sns.heatmap(cm_test, annot=True, fmt='d', cmap='Blues',
            xticklabels=CLASS_NAMES, yticklabels=CLASS_NAMES,
            cbar_kws={'label': 'Número de muestras'},
            annot_kws={'size': 14, 'weight': 'bold'})
ax.set_xlabel('Clase Predicha', fontsize=13, fontweight='bold')
ax.set_ylabel('Clase Real', fontsize=13, fontweight='bold')
ax.set_title(f'Matriz de Confusión - Test Set\nÁrbol de Decisión (Profundidad 3)',
             fontsize=14, fontweight='bold', pad=20)
plt.xticks(rotation=0, fontsize=12)
plt.yticks(rotation=0, fontsize=12)
plt.tight_layout()
plt.savefig(f'{PLOTS_DIR}/02_confusion_matrix_test.png', dpi=300, bbox_inches='tight')
plt.close()

# Gráfica 3: Curvas Precision-Recall por clase
fig, ax = plt.subplots(figsize=(10, 7))
y_proba_test = results_test['y_proba']
if y_proba_test is not None:
    for i, class_name in enumerate(CLASS_NAMES):
        y_binary = (y_test == i).astype(int)
        precision, recall, _ = precision_recall_curve(y_binary, y_proba_test[:, i])
        avg_precision = average_precision_score(y_binary, y_proba_test[:, i])
        ax.plot(recall, precision, color=CLASS_COLORS[i], lw=2.5,
                label=f'{class_name} (AP = {avg_precision:.3f})')
ax.set_xlabel('Recall', fontsize=13, fontweight='bold')
ax.set_ylabel('Precision', fontsize=13, fontweight='bold')
ax.set_title('Curvas Precision-Recall por Clase (Test)', fontsize=14, fontweight='bold')
ax.legend(loc='lower left', fontsize=11)
ax.set_xlim([0.0, 1.05])
ax.set_ylim([0.0, 1.05])
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig(f'{PLOTS_DIR}/03_precision_recall_curves.png', dpi=300, bbox_inches='tight')
plt.close()

# Gráfica 4: Importancia de features
fig, ax = plt.subplots(figsize=(10, 8))
feature_df = pd.DataFrame({'Feature': FEATURES, 'Importance': importances}).sort_values('Importance')
colors = plt.cm.viridis(np.linspace(0.3, 0.9, len(feature_df)))
bars = ax.barh(feature_df['Feature'], feature_df['Importance'], color=colors, edgecolor='black', linewidth=0.8)
ax.set_xlabel('Importancia (Gini)', fontsize=12, fontweight='bold')
ax.set_title('Importancia de Features en el Árbol de Decisión', fontsize=13, fontweight='bold')
for bar, imp in zip(bars, feature_df['Importance']):
    if imp > 0.01:
        ax.text(bar.get_width() + 0.005, bar.get_y() + bar.get_height()/2,
                f'{imp:.3f}', va='center', fontsize=9, fontweight='bold')
ax.grid(True, axis='x', alpha=0.3)
plt.tight_layout()
plt.savefig(f'{PLOTS_DIR}/04_feature_importance.png', dpi=300, bbox_inches='tight')
plt.close()

# Gráfica 5: Visualización del árbol (XAI)
fig, ax = plt.subplots(figsize=(22, 14))
plot_tree(tree, feature_names=FEATURES, class_names=CLASS_NAMES,
          filled=True, rounded=True, impurity=False,
          proportion=True, fontsize=10, ax=ax)
ax.set_title('Árbol de Decisión Entrenado (XAI)\nRuta de decisión explícita',
             fontsize=14, fontweight='bold', pad=20)
plt.tight_layout()
plt.savefig(f'{PLOTS_DIR}/05_decision_tree.png', dpi=300, bbox_inches='tight')
plt.close()

# Gráfica 6: Resumen de métricas
fig, axes = plt.subplots(1, 2, figsize=(14, 6))
ax = axes[0]
x = np.arange(len(CLASS_NAMES))
width = 0.25
precision_vals = [test_metrics[c]['precision'] for c in CLASS_NAMES]
recall_vals = [test_metrics[c]['recall'] for c in CLASS_NAMES]
f1_vals = [test_metrics[c]['f1'] for c in CLASS_NAMES]
ax.bar(x - width, precision_vals, width, label='Precision', color='#3498db')
ax.bar(x, recall_vals, width, label='Recall', color='#e67e22')
ax.bar(x + width, f1_vals, width, label='F1-Score', color='#9b59b6')
ax.set_ylabel('Score', fontsize=12)
ax.set_title('Métricas por Clase (Test)', fontsize=13, fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels(CLASS_NAMES)
ax.legend()
ax.set_ylim(0, 1.1)
ax.grid(True, axis='y', alpha=0.3)
ax.axhline(y=0.75, color='red', linestyle='--', alpha=0.5, label='Umbral mínimo (75%)')
ax = axes[1]
fp_rates = [test_metrics[c]['fp_rate'] for c in CLASS_NAMES]
bars = ax.bar(CLASS_NAMES, fp_rates, color=CLASS_COLORS, edgecolor='black')
ax.set_ylabel('Tasa de Falsos Positivos', fontsize=12)
ax.set_title('Tasa de FP por Clase (Test)', fontsize=13, fontweight='bold')
ax.set_ylim(0, 1)
ax.grid(True, axis='y', alpha=0.3)
for bar, rate in zip(bars, fp_rates):
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.02,
            f'{rate:.2%}', ha='center', fontweight='bold')
plt.suptitle('Resumen de Rendimiento del Modelo', fontsize=14, fontweight='bold', y=1.02)
plt.tight_layout()
plt.savefig(f'{PLOTS_DIR}/06_performance_summary.png', dpi=300, bbox_inches='tight')
plt.close()

# BÚSQUEDA DE UMBRALES ÓPTIMOS Y EXPORTACIÓN 
print("\n [PASO 11] Búsqueda de umbrales y exportación a Flutter...")

print("\n Buscando umbrales óptimos en Validation set...")

y_val_proba = tree.predict_proba(X_val_scaled)

best_thresholds = None
best_score = -1

for t_critical in np.arange(0.30, 0.80, 0.02):
    for t_anomalous in np.arange(0.25, 0.65, 0.02):
        y_pred_custom = []
        for proba in y_val_proba:
            if proba[2] >= t_critical:
                y_pred_custom.append(2)
            elif proba[1] >= t_anomalous:
                y_pred_custom.append(1)
            else:
                y_pred_custom.append(0)
        
        y_pred_custom = np.array(y_pred_custom)
        cm_custom = confusion_matrix(y_val, y_pred_custom, labels=[0, 1, 2])
        
        tp_critical = cm_custom[2, 2]
        fp_critical = cm_custom[0, 2] + cm_custom[1, 2]
        fn_critical = cm_custom[2, 0] + cm_custom[2, 1]
        
        precision_critical = tp_critical / (tp_critical + fp_critical + 1e-10)
        recall_critical = tp_critical / (tp_critical + fn_critical + 1e-10)
        f1_critical = 2 * precision_critical * recall_critical / (precision_critical + recall_critical + 1e-10)
        
        fp_normal_to_critical = cm_custom[0, 2]
        total_normals = cm_custom[0].sum()
        fp_normal_rate = fp_normal_to_critical / max(1, total_normals)
        
        score = (
            f1_critical * 0.4 +
            precision_critical * 0.3 +
            (1 - fp_normal_rate) * 0.3
        )
        
        # Solo considera si precision Crítico >= 0.75
        if precision_critical >= 0.75 and score > best_score:
            best_score = score
            best_thresholds = (t_anomalous, t_critical)

if best_thresholds:
    t_anomalous, t_critical = best_thresholds
    print(f"    Mejores umbrales encontrados:")
    print(f"      Anómalo: {t_anomalous:.3f}")
    print(f"      Crítico: {t_critical:.3f}")
    print(f"      Score: {best_score:.3f}")
else:
    print("     No se encontraron umbrales con precision >= 0.75")
    print("   Usando umbrales por defecto")
    t_anomalous, t_critical = 0.50, 0.50

scaler_params = {
    'mean': scaler.mean_.tolist(),
    'scale': scaler.scale_.tolist(),
    'feature_names': FEATURES,
}
with open('assets/ml/tree_scaler_params.json', 'w') as f:
    json.dump(scaler_params, f, indent=2)
print("    assets/ml/tree_scaler_params.json")

threshold_params = {
    'threshold_anomalous': float(t_anomalous),
    'threshold_critical': float(t_critical),
    'search_method': 'grid_search_on_validation',
    'precision_critical_constraint': 0.75,
    'best_score': float(best_score),
}
with open('assets/ml/threshold_params.json', 'w') as f:
    json.dump(threshold_params, f, indent=2)
print("    assets/ml/threshold_params.json")

# Exportar reglas del árbol a Dart

def generate_dart_tree(tree_model, feature_names):
    tree_ = tree_model.tree_
    def traverse(node_id, depth=0):
        indent = "  " * depth
        if tree_.feature[node_id] == -2:
            values = tree_.value[node_id][0]
            probs = values / values.sum()
            return f"{indent}return [{probs[0]:.4f}, {probs[1]:.4f}, {probs[2]:.4f}];"
        feature_idx = tree_.feature[node_id]
        threshold = tree_.threshold[node_id]
        feature_name = feature_names[feature_idx]
        code = f"{indent}if (x[{feature_idx}] < {threshold:.4f}) {{ // {feature_name}\n"
        code += traverse(tree_.children_left[node_id], depth + 1) + "\n"
        code += f"{indent}}} else {{\n"
        code += traverse(tree_.children_right[node_id], depth + 1) + "\n"
        code += f"{indent}}}"
        return code
    return traverse(0)

dart_code = generate_dart_tree(tree, FEATURES)
with open('training/generated_tree_rules.dart', 'w') as f:
    f.write(dart_code)
print("    training/generated_tree_rules.dart")

print("\n Archivos generados:")
for filepath in [
    'assets/ml/tree_scaler_params.json',
    'assets/ml/threshold_params.json',
    'training/generated_tree_rules.dart',
]:
    if os.path.exists(filepath):
        size = os.path.getsize(filepath)
        print(f"    {filepath} ({size} bytes)")
    else:
        print(f"    {filepath} (NO EXISTE)")

print("\n Verificaciones de ausencia de leakage:")
print(f"   • Usuarios en Train  Val: {len(train_users & val_users)} (debe ser 0)")
print(f"   • Usuarios en Train ∩ Test: {len(train_users & test_users)} (debe ser 0)")
print(f"   • Usuarios en Val ∩ Test: {len(val_users & test_users)} (debe ser 0)")
print(f"   • Scaler fit en: solo Train ")
print(f"   • SMOTE aplicado en: solo Train ")
print(f"   • Test set nunca usado para optimización ")

print("\n Métricas finales (Test set):")
print(f"   Accuracy: {results_test['accuracy']:.3f}")
print(f"   Macro F1: {results_test['macro_f1']:.3f}")
for class_name in CLASS_NAMES:
    m = test_metrics[class_name]
    print(f"   {class_name:10s}: P={m['precision']:.3f}  R={m['recall']:.3f}  F1={m['f1']:.3f}")

print("\n Archivos generados:")
print(f"   • training/plots/*.png")
print(f"   • assets/ml/tree_scaler_params.json")
print(f"   • training/generated_tree_rules.dart")

print("\n" + "=" * 70)
print(" ENTRENAMIENTO COMPLETADO")
print("=" * 70)