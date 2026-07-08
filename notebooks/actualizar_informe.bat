@echo off
setlocal
cd /d "%~dp0"

echo Ejecutando notebook cubo_unificado_runner.ipynb (Redshift, requiere red/VPN corporativa)...
python -m nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=600 cubo_unificado_runner.ipynb

if errorlevel 1 (
    echo.
    echo Hubo un error ejecutando el notebook. Revisa la conexion a Redshift ^(VPN^) y las credenciales en credenciales_local.py.
    pause
    exit /b 1
)

echo.
echo Listo. Se actualizaron reports\tablero_calidad_primas.html y reports\cubo_unificado.csv.
start "" "..\reports\tablero_calidad_primas.html"
pause
