import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/gpu/gpu_shader_lab.dart';
import 'lua_sandbox.dart';

/// Herramientas de agente (estilo FilosoIA tools/) con permisos.
/// El manager chequea el permiso ANTES de ejecutar; acá va la lógica pura.

enum AgentPermission { readFiles, writeFiles, webAccess, controlGui, gpuRun }

extension AgentPermissionX on AgentPermission {
  String get label => switch (this) {
        AgentPermission.readFiles => 'Leer archivos',
        AgentPermission.writeFiles => 'Escribir archivos',
        AgentPermission.webAccess => 'Acceso a web',
        AgentPermission.controlGui => 'Lua / GUI del motor',
        AgentPermission.gpuRun => 'Ejecutar shaders GPU',
      };
}

class ToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final AgentPermission permission;
  const ToolDef(this.name, this.description, this.parameters, this.permission);

  Map<String, dynamic> toSchema() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

const _obj = {
  'type': 'object',
  'properties': <String, dynamic>{},
  'required': <String>[],
};

final List<ToolDef> AGENT_TOOLS = [
  ToolDef(
    'read_file',
    'Lee un archivo de texto dentro de las carpetas de la app. '
        'Rutas relativas se resuelven desde Documentos.',
    {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'ruta relativa o absoluta'}
      },
      'required': ['path'],
    },
    AgentPermission.readFiles,
  ),
  ToolDef(
    'write_file',
    'Crea o sobrescribe un archivo de texto en las carpetas de la app.',
    {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
        'content': {'type': 'string'},
      },
      'required': ['path', 'content'],
    },
    AgentPermission.writeFiles,
  ),
  ToolDef(
    'list_dir',
    'Lista los archivos de una carpeta de la app.',
    {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': "'.' = raíz de Documentos"}
      },
      'required': ['path'],
    },
    AgentPermission.readFiles,
  ),
  ToolDef(
    'web_fetch',
    'Descarga una URL http(s) y retorna el texto (HTML sin etiquetas). '
        'Sirve para buscar/leer páginas y documentos remotos.',
    {
      'type': 'object',
      'properties': {
        'url': {'type': 'string'}
      },
      'required': ['url'],
    },
    AgentPermission.webAccess,
  ),
  ToolDef(
    'parse_local_doc',
    'Abre un documento local (.md .txt .json .lua .html) y devuelve su texto.',
    {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'}
      },
      'required': ['path'],
    },
    AgentPermission.readFiles,
  ),
  ToolDef(
    'lua_gui',
    'Ejecuta código Lua del motor pr_app que construye una página con la API '
        "gui_* (gui_heading, gui_text, gui_button, gui_input...). "
        'El usuario luego puede VER esa GUI generada.',
    {
      'type': 'object',
      'properties': {
        'code': {'type': 'string', 'description': 'script Lua completo'}
      },
      'required': ['code'],
    },
    AgentPermission.controlGui,
  ),
  ToolDef(
    'gpu_run',
    'Compila y ejecuta un shader WGSL sobre N elementos en la GPU '
        '(WebGPU/Vulkan). Retorna los primeros valores y el tiempo.',
    {
      'type': 'object',
      'properties': {
        'wgsl': {'type': 'string', 'description': 'código WGSL con @compute'},
        'n': {'type': 'integer', 'description': 'cantidad de elementos'},
      },
      'required': ['wgsl', 'n'],
    },
    AgentPermission.gpuRun,
  ),
];

ToolDef? toolByName(String n) {
  for (final t in AGENT_TOOLS) {
    if (t.name == n) return t;
  }
  return null;
}

// ------------------------------------------------------------- sandbox

Future<Directory> _docsDir() async => Directory((await getApplicationDocumentsDirectory()).path);

/// Resuelve ruta y garantiza que quede DENTRO de las carpetas de la app.
Future<String?> _resolveSandboxed(String path) async {
  final docs = await _docsDir();
  final sup = await getApplicationSupportDirectory();
  String p = path.trim();
  if (p.startsWith('./')) p = p.substring(2);
  final f = p.startsWith('/')
      ? File(p)
      : File('${docs.path}${Platform.pathSeparator}$p');
  final canonical = f.parent.resolveSymbolicLinksSync();
  if (!canonical.startsWith(docs.path) && !canonical.startsWith(sup.path)) {
    return null; // fuera del sandbox
  }
  return f.path;
}

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}\n…[truncado ${s.length} chars]';

String stripHtml(String html) {
  var t = html.replaceAll(RegExp(r'<script[^>]*>.*?</script>',
      dotAll: true, multiLine: true), '');
  t = t.replaceAll(RegExp(r'<style[^>]*>.*?</style>',
      dotAll: true, multiLine: true), '');
  t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
  t = t.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ------------------------------------------------------------- ejecutor

/// Ejecuta una tool YA AUTORIZADA. Nunca lanza: devuelve texto (o error).
Future<String> executeTool(String name, Map<String, dynamic> args) async {
  try {
    switch (name) {
      case 'read_file':
      case 'parse_local_doc':
        final path = await _resolveSandboxed(args['path'] ?? '.');
        if (path == null) return 'ERROR: ruta fuera del sandbox de la app';
        final f = File(path);
        if (!f.existsSync()) return 'ERROR: no existe $path';
        return _clip(f.readAsStringSync(), 20000);

      case 'write_file':
        final path = await _resolveSandboxed(args['path'] ?? '');
        if (path == null) return 'ERROR: ruta fuera del sandbox de la app';
        File(path).parent.createSync(recursive: true);
        File(path).writeAsStringSync(args['content'] ?? '');
        return 'OK: escrito ${File(path).lengthSync()} bytes en $path';

      case 'list_dir':
        final path = await _resolveSandboxed(args['path'] ?? '.');
        if (path == null) return 'ERROR: fuera del sandbox';
        final d =
            FileSystemEntity.isDirectorySync(path) ? Directory(path) : null;
        if (d == null || !d.existsSync()) return 'ERROR: carpeta inexistente';
        return _clip(d.listSync().map((e) {
          final tag = e is Directory ? '[d] ' : '[f] ';
          return '$tag${e.path.split(Platform.pathSeparator).last}';
        }).join('\n'), 8000);

      case 'web_fetch':
        final url = args['url'] ?? '';
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return 'ERROR: HTTP ${res.statusCode}';
        final ct = res.headers['content-type'] ?? '';
        final text =
            ct.contains('html') ? stripHtml(res.body) : res.body;
        return _clip(text, 15000);

      case 'lua_gui':
        final page = LuaSandbox.instance.run(args['code'] ?? '');
        if (page == null) {
          return 'ERROR: el script Lua no compiló o no definió `page`';
        }
        LuaSandbox.instance.markDirty();
        return 'OK GUI generada: "${page.title}" con ${page.body.length} widgets. '
            'Avisale al usuario que toque "Ver GUI" en tu tarjeta.';

      case 'gpu_run':
        final lab = GpuShaderLab();
        final r = await lab.run(
          code: args['wgsl'] ?? '',
          input: List.generate(
              ((args['n'] ?? 64) as num).toInt().clamp(8, 1 << 20),
              (i) => i.toDouble()),
          dispatchX: ((((args['n'] ?? 64) as num).toInt()) + 63) ~/ 64,
          dispatchY: 1,
          dispatchZ: 1,
          paramX: 2.0,
          paramY: 0,
          paramZ: 0,
        );
        if (!r.ok) return 'ERROR GPU: ${r.error}';
        return 'OK GPU (${r.elapsedMs.toStringAsFixed(2)} ms): '
            '${r.data.take(8).map((v) => v.toStringAsFixed(3)).join('  ')}';

      default:
        return 'ERROR: herramienta desconocida $name';
    }
  } catch (e) {
    return 'ERROR ejecutando $name: $e';
  }
}

/// Args vienen como string JSON del LLM → mapa tolerante.
Map<String, dynamic> parseToolArgs(String raw) {
  try {
    final v = jsonDecode(raw.isEmpty ? '{}' : raw);
    return v is Map<String, dynamic> ? v : {};
  } catch (_) {
    return {};
  }
}
