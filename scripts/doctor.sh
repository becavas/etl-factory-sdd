#!/usr/bin/env bash
# Comprobación del entorno de M01.
set -uo pipefail
mode="${1:-offline}"
if [ "$#" -gt 1 ]; then
  printf 'Uso: bash scripts/doctor.sh [offline|conectado]\n' >&2
  exit 2
fi
case "$mode" in
  offline|conectado) ;;
  *) printf 'Uso: bash scripts/doctor.sh [offline|conectado]\n' >&2; exit 2 ;;
esac
failed=0
ok() { printf 'OK %s\n' "$1"; }
fail() { printf 'FALLO %s\n' "$1"; failed=1; }
version() {
  label="$1"; pattern="$2"; shift 2
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$label no disponible en PATH"; return
  fi
  if output=$("$@" 2>&1) && printf '%s\n' "$output" | grep -Eq "$pattern"; then
    ok "$label compatible"
  else
    fail "$label fuera de la matriz o no responde"
  fi
}
version Conda '^conda [0-9]+\.' conda --version
active_env="${CONDA_DEFAULT_ENV:-}"
if [ "${active_env##*/}" = etl-factory-sdd ]; then
  ok 'entorno Conda activo'
else
  fail 'activa conda activate etl-factory-sdd'
fi
version Python '^3\.12\.[0-9]+$' python -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'
version Git '^git version ([2-9]|[1-9][0-9]+)\.' git --version
version gh '^gh version ([2-9]|[1-9][0-9]+)\.' gh --version
version Databricks '^Databricks CLI v1\.24\.0$' databricks version
version Java '^(openjdk|java) version "21\.' java -version
version PySpark '^4\.1\.0$' python -c 'from importlib.metadata import version; print(version("pyspark"))'
version Delta '^4\.2\.0$' python -c 'from importlib.metadata import version; print(version("delta-spark"))'
version Node '^v24\.[0-9]+\.[0-9]+$' node --version
version npm '^[0-9]+\.[0-9]+\.[0-9]+$' npm --version
version OpenSpec '^1\.14\.3$' openspec --version
version Claude '^[0-9]+\.[0-9]+\.[0-9]+' claude --version
for tool in make curl tar jq rg; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool disponible"; else fail "$tool no disponible"; fi
done
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$(git config --get user.name)" ] && [ -n "$(git config --get user.email)" ]; then
    ok 'identidad Git configurada'
  else fail 'configura user.name y user.email'; fi
  if git remote get-url origin >/dev/null 2>&1; then ok 'origin configurado'; else fail 'falta origin'; fi
else fail 'ejecuta desde tu repositorio Git'; fi
# No ejecutar consultas conectadas con una base local incompatible.
if [ "$failed" -ne 0 ]; then exit 1; fi
if [ "$mode" = offline ]; then
  printf 'doctor: local OK; acceso GitHub, Claude y sandbox sin comprobar\n'
  exit 0
fi
# Verificar el destino y la forma de autenticación antes de cualquier consulta.
if ! python - <<'PY'
import configparser
import os
import sys
from pathlib import Path
from urllib.parse import urlsplit


def reject():
    print("FALLO ficha sandbox, perfil U2M o entorno de autenticación incompatible")
    sys.exit(1)


if any(k.startswith("DATABRICKS_") and k != "DATABRICKS_CONFIG_FILE" for k in os.environ):
    reject()
host = os.environ.get("SANDBOX_HOST", "").rstrip("/")
user = os.environ.get("SANDBOX_USER", "")
try:
    parsed = urlsplit(host)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.path or parsed.query or parsed.fragment or not user):
        reject()
    config = configparser.ConfigParser(interpolation=None)
    path = Path(os.environ.get("DATABRICKS_CONFIG_FILE", "~/.databrickscfg")).expanduser()
    config.read(path)
    profile = config["sandbox"]
    if profile.get("host", "").rstrip("/") != host:
        reject()
    if profile.get("auth_type") != "databricks-cli":
        reject()
    if any(profile.get(k) for k in ("token", "client_secret", "password", "username", "client_id")):
        reject()
except (KeyError, ValueError, OSError, configparser.Error):
    reject()
print("OK destino sandbox y perfil OAuth U2M contrastados con la ficha")
PY
then exit 1; fi
if gh auth status >/dev/null 2>&1; then ok 'sesión GitHub disponible'; else fail 'ejecuta gh auth login'; fi
if current_user=$(databricks current-user me --profile sandbox -o json 2>/dev/null); then
  if printf '%s' "$current_user" | python -c 'import json,os,sys; value=json.load(sys.stdin).get("userName"); sys.exit(0 if value and value == os.environ["SANDBOX_USER"] else 1)' 2>/dev/null; then
    ok 'identidad sandbox coincide con la ficha'
  else fail 'identidad sandbox distinta o respuesta inválida'; fi
else fail 'consulta sandbox fallida; revisa login, red y permisos'; fi
if [ "$failed" -ne 0 ]; then exit 1; fi
printf 'doctor: conectado OK; verifica aparte la sesión interactiva de Claude\n'
