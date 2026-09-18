import 'colab_task_models.dart';

/// Prefabs de tareas Colab: plantillas listas (el usuario solo manda
/// el argumento). El código Python es autocontenido para el kernel.
abstract final class ColabPrefabs {
  static const prefabCdnHfNombre = 'CDN → cifrar → HF';

  /// Argumento (5 líneas, en este orden):
  ///   1. URL del CDN a descargar
  ///   2. pass del CDN/lote (sellada al inicio)
  ///   3. token HF (write) para subir
  ///   4. repo destino dir/user (ej. miuser/mis-lotes)
  ///   5. pass GLOBAL (cifra todo: sin esto no se recupera
  ///      ni archivo ni pass del CDN)
  ///
  /// Todo con CLIs de golo (se clona si falta). El GLOBAL cifra
  /// todo de una: `global(cdn_pass + cdn)` = pass del lote pegada
  /// primero + archivo, un solo PRBX con el maestro.
  /// Formato: `PRBX(maestro, [u32be len_pass][passCdn][datos])`.
  static ColabTask cdnCifrarHf() => ColabTask(
        id: 'prefab-cdn-hf',
        nombre: prefabCdnHfNombre,
        hasArg: true,
        code: _kCdnCifrarHf,
      );

  // Todo con CLIs de golo (download, enc x2, hf). Dos passes:
  // maestro (sella el lote) + lote (cifra el contenido).
  static const _kCdnCifrarHf = '''
import os, shutil, struct, subprocess, sys

GOLO = "/tmp/golo"
if not os.path.isdir(os.path.join(GOLO, "python")):
    subprocess.run(["git", "clone", "--depth", "1",
                    "https://github.com/elmasber-ma/golo.git", GOLO],
                   check=True)

def sh(args, cwd):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("fallo (%d): %s" % (r.returncode,
                                             r.stderr.strip()[-500:]))
    return r.stdout.strip()

lineas = [l.strip() for l in ARG.strip().splitlines() if l.strip()]
if len(lineas) < 5:
    raise SystemExit("ARG necesita 5 lineas: URL, PASS_CDN, "
                     "HF_TOKEN, user/repo, PASS_GLOBAL")
url, lote, token, repo, maestro = lineas[0], lineas[1], lineas[2], lineas[3], lineas[4]
nombre = url.split("?")[0].rstrip("/").split("/")[-1] or "lote.bin"

print("fase 1", flush=True)
sh([sys.executable, "python/deps.py"], GOLO + "/python")
sh([sys.executable, "-m", "pip", "install", "--quiet",
    "-r", "requirements.txt"], GOLO + "/hf")
try:
    import requests  # noqa
except ImportError:
    sh([sys.executable, "-m", "pip", "install", "--quiet", "requests"],
       GOLO + "/hf")

print("fase 2", flush=True)
sh([sys.executable, "download/cli.py", url, "/tmp/lote",
    "--file", nombre], GOLO)
crudo = "/tmp/lote/" + nombre

print("fase 3", flush=True)
with open("/tmp/lote.pass", "wb") as f:
    pb = lote.encode()
    f.write(b"LOTE")
    f.write(struct.pack(">I", len(pb)))
    f.write(pb)
a = open("/tmp/lote.pass", "rb")
b = open(crudo, "rb")
f = open("/tmp/lote.pegado", "wb")
shutil.copyfileobj(a, f)
shutil.copyfileobj(b, f, 1024 * 1024)
a.close()
b.close()
f.close()

print("fase 4", flush=True)
sh([sys.executable, "python/cli.py", "enc", maestro, "/tmp/lote.pegado",
    "/tmp/" + nombre + ".prbx"], GOLO + "/python")
final = "/tmp/" + nombre + ".prbx"

print("fase 5", flush=True)
sh([sys.executable, "hf/cli.py", token, final, repo,
    "--repo-type", "dataset", "--private"], GOLO + "/hf")
print("ok", flush=True)
''';
}
