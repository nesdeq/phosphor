import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A discovered CLI tool on the system.
class CliTool {
  final String name;

  const CliTool({required this.name});
}

/// Detected project type from config files.
enum ProjectType {
  node('Node.js', ['npm', 'npx', 'yarn', 'pnpm', 'bun']),
  python('Python', ['python', 'pip', 'uv', 'poetry', 'pytest']),
  rust('Rust', ['cargo', 'rustc', 'rustup']),
  go('Go', ['go']),
  dart('Dart/Flutter', ['dart', 'flutter', 'pub']),
  ruby('Ruby', ['ruby', 'gem', 'bundle', 'rails']),
  java('Java', ['java', 'javac', 'mvn', 'gradle']),
  docker('Docker', ['docker', 'docker-compose', 'kubectl']),
  git('Git', ['git', 'gh', 'glab']),
  unknown('Unknown', []);

  const ProjectType(this.label, this.relatedTools);
  final String label;
  final List<String> relatedTools;
}

/// Scans the system for installed CLI tools and detects project context.
final cliIntelligenceProvider = Provider<CliIntelligence>((ref) {
  return CliIntelligence();
});

/// Registry of installed tools, rebuilt on demand.
final toolRegistryProvider = FutureProvider<List<CliTool>>((ref) async {
  final cli = ref.watch(cliIntelligenceProvider);
  return cli.scanTools();
});

/// Detected project type for the current working directory.
final projectTypeProvider = FutureProvider<ProjectType>((ref) async {
  final cli = ref.watch(cliIntelligenceProvider);
  return cli.detectProjectType(Directory.current.path);
});

class CliIntelligence {
  /// Well-known CLI tools to look for.
  static const _knownTools = [
    'git',
    'gh',
    'docker',
    'kubectl',
    'helm',
    'node',
    'npm',
    'npx',
    'yarn',
    'pnpm',
    'bun',
    'deno',
    'python',
    'python3',
    'pip',
    'uv',
    'poetry',
    'conda',
    'cargo',
    'rustc',
    'rustup',
    'go',
    'dart',
    'flutter',
    'pub',
    'ruby',
    'gem',
    'bundle',
    'rails',
    'java',
    'javac',
    'mvn',
    'gradle',
    'aws',
    'gcloud',
    'az',
    'terraform',
    'pulumi',
    'curl',
    'wget',
    'httpie',
    'jq',
    'yq',
    'fx',
    'tmux',
    'screen',
    'vim',
    'nvim',
    'emacs',
    'rg',
    'fd',
    'fzf',
    'bat',
    'eza',
    'zoxide',
    'sqlite3',
    'psql',
    'mysql',
    'redis-cli',
    'mongosh',
    'ffmpeg',
    'imagemagick',
    'pandoc',
    'make',
    'cmake',
    'ninja',
    'ssh',
    'scp',
    'rsync',
    'brew',
    'apt',
    'dnf',
    'pacman',
  ];

  /// Project config file -> project type mapping.
  static const _projectIndicators = {
    'package.json': ProjectType.node,
    'pyproject.toml': ProjectType.python,
    'setup.py': ProjectType.python,
    'requirements.txt': ProjectType.python,
    'Cargo.toml': ProjectType.rust,
    'go.mod': ProjectType.go,
    'pubspec.yaml': ProjectType.dart,
    'Gemfile': ProjectType.ruby,
    'pom.xml': ProjectType.java,
    'build.gradle': ProjectType.java,
    'Dockerfile': ProjectType.docker,
    'docker-compose.yml': ProjectType.docker,
    'docker-compose.yaml': ProjectType.docker,
    '.git': ProjectType.git,
  };

  /// Scan $PATH for known tools (parallelized).
  Future<List<CliTool>> scanTools() async {
    final results = await Future.wait(
      _knownTools.map((name) async {
        try {
          final result = await Process.run('which', [name]);
          return result.exitCode == 0 ? name : null;
        } catch (_) {
          return null;
        }
      }),
    );
    return results
        .whereType<String>()
        .map((name) => CliTool(name: name))
        .toList();
  }

  /// Detect project type by checking for config files.
  Future<ProjectType> detectProjectType(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return ProjectType.unknown;

    for (final entry in _projectIndicators.entries) {
      final file = File('$directory/${entry.key}');
      final dirCheck = Directory('$directory/${entry.key}');
      if (await file.exists() || await dirCheck.exists()) {
        return entry.value;
      }
    }

    return ProjectType.unknown;
  }
}
