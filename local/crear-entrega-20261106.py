"""Entrega de desarrollo seleccionada; no incluye respaldos ni registros de pacientes."""
from pathlib import Path
import base64
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PARENT = ROOT.parent
OUT = PARENT / 'Para otras IA'
ZIP_NAME = 'Marathon_CRM_0.14.0_actual_2026-11-06.zip'
ZIP_PATH = OUT / ZIP_NAME

def digest(data):
    return hashlib.sha256(data).hexdigest()

def main():
    OUT.mkdir(exist_ok=True)
    if ZIP_PATH.exists():
        raise RuntimeError('La entrega ya existe; no se sobrescribe automáticamente.')

    paths = set((ROOT / 'public').rglob('*'))
    paths.update((ROOT / 'supabase' / 'migrations').glob('*.sql'))
    paths.update((ROOT / 'supabase').glob('*.sql'))
    paths.add(ROOT / 'supabase' / 'LEEME.md')
    for folder in ('supabase/functions', 'supabase/tests', 'tests'):
        for p in (ROOT / folder).rglob('*'):
            if p.suffix.lower() in ('.sql', '.py', '.mjs', '.js', '.ts', '.md', '.toml'):
                paths.add(p)
    for relative in (
        'README.md', 'marathon-install.json', 'local/servidor.cjs',
        'Documentacion/ESTADO_ACTUAL.md',
        'Documentacion/CONTEXTO_PARA_OTRA_IA.md',
        'Documentacion/MAPA_DE_ARCHIVOS.md',
        'Documentacion/PENDIENTES_DEL_INFORME.md',
        'Documentacion/MANUAL_USO_ACTUAL.md',
        'Documentacion/INFORME_PPS_ACTUALIZADO.md',
        'Documentacion/DICCIONARIO_SUPABASE_20261106.json',
        'Documentacion/ACTUALIZACION_INFORME_DRIVE_20261106.json',
        'Documentacion/GUIA_EDITAR_CANCELAR_SERIES.md',
        'Documentacion/GUIA_EXCEL_INFORMES.md',
        'Documentacion/Caja_saldo_a_favor/GUIA_USO_ACTIVA.md',
        'Documentacion/DESPLIEGUE_20261106_editar_secretarias.json',
        'Documentacion/DESPLIEGUE_20261106_editar_ingreso.json',
        'Documentacion/DESPLIEGUE_20261106_caja_profesional.json',
        'Documentacion/DESPLIEGUE_20261106_atencion_excepcional.json',
        'Documentacion/DESPLIEGUE_20261105_mensual_fechas.json',
        'Documentacion/DESPLIEGUE_20261105_excel_informes.json',
        'Documentacion/MANIFIESTO_20261106_editar_secretarias.json',
        'Documentacion/VERIFICACION_ENTREGA_20261106.json',
    ):
        paths.add(ROOT / relative)

    paths = sorted((p for p in paths if p.is_file()), key=lambda p: p.as_posix())
    payload = {}
    blocked = []
    forbidden_parts = {'__pycache__', 'node_modules', '.temp', '.git', 'logs'}
    secret_patterns = [
        re.compile(r'sb_secret_[A-Za-z0-9_-]{15,}'),
        re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
        re.compile(r'postgres(?:ql)?://[^\s\x22\x27]+:[^\s\x22\x27@]+@'),
    ]
    for p in paths:
        resolved = p.resolve()
        if not resolved.is_relative_to(ROOT):
            raise RuntimeError('Archivo fuera del proyecto: ' + p.name)
        relative = p.relative_to(ROOT).as_posix()
        if any(part in forbidden_parts for part in p.relative_to(ROOT).parts):
            raise RuntimeError('Carpeta excluida en la selección: ' + relative)
        if p.name.startswith('.env') or p.suffix.lower() in ('.dump', '.bak', '.exe', '.rar', '.zip', '.log'):
            raise RuntimeError('Archivo no permitido: ' + relative)
        data = p.read_bytes()
        if p.suffix.lower() in ('.js', '.mjs', '.ts', '.sql', '.json', '.py', '.md', '.html'):
            text = data.decode('utf-8-sig')
            if any(pattern.search(text) for pattern in secret_patterns):
                blocked.append(relative)
            for token in re.findall(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', text):
                try:
                    encoded = token.split('.')[1]
                    claims = json.loads(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)))
                    if claims.get('role') == 'service_role':
                        blocked.append(relative)
                except (ValueError, UnicodeDecodeError):
                    pass
        payload[relative] = data
    if blocked:
        raise RuntimeError('Revisar posibles secretos en: ' + ', '.join(sorted(set(blocked))))

    production_manifest = json.loads(payload['Documentacion/MANIFIESTO_20261106_editar_secretarias.json'])
    for row in production_manifest:
        relative = 'public/' + row['relative']
        if relative not in payload or hashlib.sha1(payload[relative]).hexdigest() != row['sha']:
            raise RuntimeError('El código difiere del manifiesto publicado: ' + relative)
    index = payload['public/index.html'].decode('utf-8')
    operations = payload['public/operations.js'].decode('utf-8')
    if 'editar-secretarias-1' not in index or "['ADMIN','SECRETARIA'].includes" not in operations:
        raise RuntimeError('No corresponde a la revisión vigente.')
    if '20261106225955_caja_edicion_secretarias.sql' not in '\n'.join(payload):
        raise RuntimeError('Falta la migración vigente.')
    report = payload['Documentacion/INFORME_PPS_ACTUALIZADO.md'].decode('utf-8')
    for section in ('Producto mínimo viable', 'Mejora continua', 'Utilidad para la toma de decisiones', 'Propuesta de distribución por obra social', 'Propuesta de indicadores de stock'):
        if section not in report:
            raise RuntimeError('Falta una sección actualizada del informe: ' + section)

    manifest = {
        'date': '2026-11-06',
        'base_version': '0.14.0',
        'revision': 'editar-secretarias-1',
        'deployment': 'dpl_3vspdZu7ivx6LjuAzcPDQrwTGXho',
        'latest_migration': '20261106225955_caja_edicion_secretarias.sql',
        'scope': 'Desarrollo y documentación seleccionada; no es un respaldo de base ni un instalador de Supabase.',
        'files': [{'path': name, 'bytes': len(data), 'sha256': digest(data)} for name, data in sorted(payload.items())],
    }
    manifest_data = json.dumps(manifest, ensure_ascii=False, indent=2).encode('utf-8')
    with zipfile.ZipFile(ZIP_PATH, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(payload.items()):
            z.writestr(name, data)
        z.writestr('ENTREGA_MANIFIESTO.json', manifest_data)

    with zipfile.ZipFile(ZIP_PATH) as z:
        if z.testzip() is not None:
            raise RuntimeError('Error de integridad CRC en el ZIP.')
        if set(z.namelist()) != set(payload) | {'ENTREGA_MANIFIESTO.json'}:
            raise RuntimeError('Contenido inesperado en el ZIP.')
        for row in manifest['files']:
            if digest(z.read(row['path'])) != row['sha256']:
                raise RuntimeError('No coincide un archivo comprimido: ' + row['path'])
    checksum = digest(ZIP_PATH.read_bytes())
    ZIP_PATH.with_name(ZIP_NAME + '.sha256.txt').write_text(checksum + '  ' + ZIP_NAME + '\n', encoding='utf-8')
    result = {
        'zip': str(ZIP_PATH), 'bytes': ZIP_PATH.stat().st_size,
        'sha256': checksum, 'files': len(payload) + 1,
        'public_files': len(production_manifest),
        'latest_revision': manifest['revision'],
        'crc_verified': True, 'all_file_hashes_verified': True,
        'public_matches_production_manifest': True,
        'report_sections_verified': True,
        'private_backups_and_binaries_excluded': True,
    }
    (OUT / 'VERIFICACION_ENTREGA_20261106.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=True))

if __name__ == '__main__':
    main()
