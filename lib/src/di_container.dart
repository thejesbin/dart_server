import 'controller.dart';
import 'module.dart';

/// Builds the module graph from a root [Module], wires up dependency injection
/// with per-module encapsulation, and bootstraps singletons and controllers.
///
/// Internal to the framework — used by `DartServerFactory`.
class ModuleContainer {
  ModuleContainer(Module root) {
    _collect(root);
    _computeGlobals();
    // Validate every module's exports up front (even the root's), so a module
    // that exports a token it doesn't provide fails fast regardless of whether
    // anything imports it.
    for (final node in _nodes.values) {
      _exportsOf(node);
    }
    for (final node in _nodes.values) {
      node.visible = _computeVisible(node);
    }
  }

  final Map<Module, _ModuleNode> _nodes = {};
  // Modules in dependency order: imports appear before importers.
  final List<_ModuleNode> _order = [];
  final List<_GlobalExport> _globals = [];

  final Map<Provider, Object> _singletons = {};
  final Set<Provider> _resolving = {};
  final Map<_ModuleNode, _ScopedInjector> _injectors = {};
  final Map<_ModuleNode, Map<Type, _Binding>> _exportCache = {};
  final Set<_ModuleNode> _exportInProgress = {};

  // Instances in creation order, for lifecycle hooks (deduped by identity).
  final List<Object> _created = [];
  final Set<Object> _seen = Set.identity();

  _ModuleNode _collect(Module module) {
    final existing = _nodes[module];
    if (existing != null) return existing;

    final node = _ModuleNode(module);
    _nodes[module] = node;
    for (final provider in module.providers) {
      if (node.own.containsKey(provider.token)) {
        throw DiError(
            'Duplicate provider for ${provider.token} in the same module.');
      }
      node.own[provider.token] = provider;
    }
    for (final imported in module.imports) {
      node.imports.add(_collect(imported));
    }
    _order.add(node);
    return node;
  }

  void _computeGlobals() {
    for (final node in _nodes.values) {
      if (!node.module.isGlobal) continue;
      for (final token in node.module.exports) {
        _globals.add(_GlobalExport(node, token));
      }
    }
  }

  /// The tokens (and the binding that satisfies each) a module exposes to
  /// importers — its own exported providers plus any it re-exports from its own
  /// imports.
  Map<Type, _Binding> _exportsOf(_ModuleNode node) {
    final cached = _exportCache[node];
    if (cached != null) return cached;
    if (!_exportInProgress.add(node)) return const {}; // break import cycles

    final result = <Type, _Binding>{};
    for (final token in node.module.exports) {
      _Binding? binding;
      final own = node.own[token];
      if (own != null) {
        binding = _Binding(node, own);
      } else {
        for (final imported in node.imports) {
          final reExported = _exportsOf(imported)[token];
          if (reExported != null) {
            binding = reExported;
            break;
          }
        }
      }
      if (binding == null) {
        throw DiError('Module exports $token but neither provides nor '
            'imports a module that exports it.');
      }
      result[token] = binding;
    }

    _exportInProgress.remove(node);
    _exportCache[node] = result;
    return result;
  }

  Map<Type, _Binding> _computeVisible(_ModuleNode node) {
    final visible = <Type, _Binding>{};
    // Globals first (lowest priority).
    for (final global in _globals) {
      final binding = _exportsOf(global.owner)[global.token];
      if (binding != null) visible[global.token] = binding;
    }
    // Then imported modules' exports.
    for (final imported in node.imports) {
      _exportsOf(imported).forEach((token, binding) {
        visible[token] = binding;
      });
    }
    // Own providers win.
    node.own.forEach((token, provider) {
      visible[token] = _Binding(node, provider);
    });
    return visible;
  }

  Object _resolve(_ModuleNode node, Type token) {
    final binding = node.visible[token];
    if (binding == null) {
      throw DiError(
          'No provider for $token is visible to this module. Declare it in the '
          "module's providers, or import a module that exports it.");
    }
    return _instantiate(binding);
  }

  Object _instantiate(_Binding binding) {
    final provider = binding.provider;
    if (provider.scope == ProviderScope.singleton) {
      final existing = _singletons[provider];
      if (existing != null) return existing;
    }
    if (!_resolving.add(provider)) {
      throw DiError('Circular dependency detected while resolving '
          '${provider.token}.');
    }
    final Object instance;
    try {
      instance = provider.create(_injectorFor(binding.owner));
    } finally {
      _resolving.remove(provider);
    }
    if (provider.scope == ProviderScope.singleton) {
      _singletons[provider] = instance;
    }
    _markCreated(instance);
    return instance;
  }

  _ScopedInjector _injectorFor(_ModuleNode node) =>
      _injectors[node] ??= _ScopedInjector(this, node);

  void _markCreated(Object instance) {
    if (_seen.add(instance)) _created.add(instance);
  }

  /// Eagerly instantiates all singleton/value providers, builds every
  /// controller, runs [OnInit] hooks in dependency order, and returns the
  /// controllers to be mounted.
  Future<List<Controller>> bootstrap() async {
    for (final node in _order) {
      for (final provider in node.own.values) {
        if (provider.scope != ProviderScope.transient) {
          _instantiate(_Binding(node, provider));
        }
      }
    }

    final controllers = <Controller>[];
    for (final node in _order) {
      final injector = _injectorFor(node);
      for (final factory in node.module.controllers) {
        final controller = factory(injector);
        _markCreated(controller);
        controllers.add(controller);
      }
    }

    for (final instance in _created) {
      if (instance is OnInit) await instance.onInit();
    }

    return controllers;
  }
}

class _ModuleNode {
  _ModuleNode(this.module);

  final Module module;
  final List<_ModuleNode> imports = [];
  final Map<Type, Provider> own = {};
  Map<Type, _Binding> visible = const {};
}

/// A resolved provider plus the module that owns it (whose injector scope is
/// used when creating it).
class _Binding {
  _Binding(this.owner, this.provider);

  final _ModuleNode owner;
  final Provider provider;
}

class _GlobalExport {
  _GlobalExport(this.owner, this.token);

  final _ModuleNode owner;
  final Type token;
}

class _ScopedInjector implements Injector {
  _ScopedInjector(this._container, this._node);

  final ModuleContainer _container;
  final _ModuleNode _node;

  @override
  T get<T extends Object>() => _container._resolve(_node, T) as T;
}
