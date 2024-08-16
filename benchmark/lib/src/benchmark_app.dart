import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class BenchmarkApp extends StatefulWidget {
  const BenchmarkApp({super.key});

  @override
  State<BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<BenchmarkApp> {
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
      PlatformDispatcher.instance.platformBrightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light);

  @override
  void initState() {
    super.initState();
    themeMode.addListener(_onChanged);
  }

  @override
  void dispose() {
    themeMode.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void toggleTheme() => themeMode.value = switch (themeMode.value) {
        ThemeMode.dark => ThemeMode.light,
        ThemeMode.light || _ => ThemeMode.dark,
      };

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Benchmark',
        themeMode: themeMode.value,
        theme: switch (themeMode.value) {
          ThemeMode.dark => ThemeData.dark(),
          ThemeMode.light || _ => ThemeData.light(),
        },
        home: _BenchmarkScaffold(
          themeMode: themeMode,
        ),
      );
}

enum Library { spinify, centrifuge }

class BenchmarkController with ChangeNotifier {
  /// Library to use for the benchmark.
  final ValueNotifier<Library> library =
      ValueNotifier<Library>(Library.centrifuge);

  /// WebSocket endpoint to connect to.
  final TextEditingController endpoint =
      TextEditingController(text: 'ws://localhost:8000/connection/websocket');

  /// Size in bytes of the payload to send/receive.
  final ValueNotifier<int> payloadSize = ValueNotifier<int>(1024 * 1024);

  /// Number of messages to send/receive.
  final ValueNotifier<int> duration = ValueNotifier<int>(1000);

  Future<void> start() async {}

  @override
  void dispose() {
    endpoint.dispose();
    super.dispose();
  }
}

class _BenchmarkScaffold extends StatefulWidget {
  const _BenchmarkScaffold({
    required this.themeMode,
    super.key, // ignore: unused_element
  });

  final ValueListenable<ThemeMode> themeMode;

  @override
  State<_BenchmarkScaffold> createState() => _BenchmarkScaffoldState();
}

class _BenchmarkScaffoldState extends State<_BenchmarkScaffold>
    with SingleTickerProviderStateMixin {
  final BenchmarkController controller = BenchmarkController();
  late final TabController tabBarController;

  @override
  void initState() {
    tabBarController = TabController(length: 2, vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    tabBarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Benchmark'),
          actions: <Widget>[
            ValueListenableBuilder(
                valueListenable: widget.themeMode,
                builder: (context, mode, _) => IconButton(
                      icon: switch (mode) {
                        ThemeMode.dark => Icon(Icons.light_mode),
                        ThemeMode.light => Icon(Icons.dark_mode),
                        ThemeMode.system => Icon(Icons.auto_awesome),
                      },
                      onPressed: () => context
                          .findAncestorStateOfType<_BenchmarkAppState>()
                          ?.toggleTheme(),
                    )),
            SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: ListenableBuilder(
            listenable: tabBarController,
            builder: (context, _) => BottomNavigationBar(
                  currentIndex: tabBarController.index,
                  onTap: (index) => tabBarController.animateTo(index),
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.speed),
                      label: 'Benchmark',
                    ),
                    /* BottomNavigationBarItem(
                    icon: Icon(Icons.device_unknown),
                    label: 'Unknown',
                  ), */
                    BottomNavigationBarItem(
                      icon: Icon(Icons.help),
                      label: 'Help',
                    ),
                  ],
                )),
        body: SafeArea(
          child: TabBarView(
            controller: tabBarController,
            children: <Widget>[
              Align(
                alignment: Alignment.topCenter,
                child: _BenchmarkTab(
                  controller: controller,
                ),
              ),
              /* Center(
              child: Text('Unknown'),
            ), */
              Center(
                child: Text('Help'),
              ),
            ],
          ),
        ),
      );
}

class _BenchmarkTab extends StatelessWidget {
  const _BenchmarkTab({
    required this.controller,
    super.key, // ignore: unused_element
  });

  final BenchmarkController controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ValueListenableBuilder<Library>(
              valueListenable: controller.library,
              builder: (context, library, _) => SegmentedButton(
                selected: {library},
                segments: <ButtonSegment<Library>>[
                  ButtonSegment<Library>(
                    value: Library.spinify,
                    label: Text('Spinify'),
                  ),
                  ButtonSegment<Library>(
                    value: Library.centrifuge,
                    label: Text('Centrifuge'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller.endpoint,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                hintText: 'ws://localhost:8000/connection/websocket',
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<int>(
              valueListenable: controller.payloadSize,
              builder: (context, size, _) => Slider(
                value: size.toDouble(),
                min: 0,
                max: 1024 * 1024 * 10,
                divisions: 100,
                label: switch (size) {
                  0 => 'Not set',
                  1 => '1 byte',
                  >= 1024 * 1024 * 1024 => '${size ~/ 1024 ~/ 1024 ~/ 100}GB',
                  >= 1024 * 1024 => '${size ~/ 1024 ~/ 1024}MB',
                  >= 1024 => '${size ~/ 1024}KB',
                  _ => '$size bytes',
                },
                onChanged: (value) =>
                    controller.payloadSize.value = value.toInt(),
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<int>(
              valueListenable: controller.duration,
              builder: (context, duration, _) => Slider(
                value: duration.toDouble(),
                min: 1,
                max: 1000000,
                divisions: 100,
                label: switch (duration) {
                  0 => 'Not set',
                  1 => '1 message',
                  >= 1000000 => '${duration ~/ 1000000}M messages',
                  >= 1000 => '${duration ~/ 1000}k messages',
                  _ => '$duration messages',
                },
                onChanged: (value) => controller.duration.value = value.toInt(),
              ),
            ),
            /* Spacer(),
              Spacer(), */
          ],
        ),
      );
}
