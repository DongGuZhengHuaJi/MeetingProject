import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart'; // 新增
import 'login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化窗口管理器
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(400, 600), // 初始登录页大小
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // 核心：取消系统标题栏
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 去掉右上角DEBUG标志更精致
      title: '会议系统',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
      // 注册路由，方便跳转
      // routes: {
      //   '/': (context) => const LoginPage(),
      //   '/home': (context) {
      //     final args = ModalRoute.of(context)?.settings.arguments;
      //     final selfId =
      //         args is Map ? (args['selfId']?.toString() ?? '') : '';
      //     return HomePage(selfId: selfId, httpMgr: HttpMgr.instance());
      //   },
      // },
    );
  }
}