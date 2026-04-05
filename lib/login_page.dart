import 'package:flutter/material.dart';
import 'package:meetingproject/websocket_mgr.dart';
import 'package:window_manager/window_manager.dart';
import 'webrtc_mgr.dart';
import 'dart:convert';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _tipText = "";
  Color _tipColor = Colors.redAccent;


  // 登录并切换窗口大小
  void _doLogin() async {
    final account = _accountController.text.trim();
    if (account.isNotEmpty && _passwordController.text == "123456") {
      setState(() {
        _tipText = "登录成功，正在进入...";
        _tipColor = Colors.green;
      });

      // 1. 改变窗口为大尺寸
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.center();
      await windowManager.setResizable(true); // 允许主页缩放

      if (!mounted) return;

      final wtm = WebRTCManager();
      // 登录时，全局初始化信令和 WebSocket，并完成注册
      await wtm.initializeSignaling(selfId: account, signalingUrl: 'ws://114.132.52.242:8080');

      Navigator.pushReplacementNamed(context, '/home', arguments: {'selfId': account});
    } else {
      setState(() {
        _tipText = "账号不能为空，密码为 123456";
        _tipColor = Colors.redAccent;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: Column(
        children: [
          // 自定义窗口栏（负责拖动和关闭）
          const WindowCaptionArea(), 
          
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 350),
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
                      ),
                      child: const Icon(Icons.person, size: 50, color: Colors.blueAccent),
                    ),
                    const SizedBox(height: 40),
                    TextField(
                      controller: _accountController,
                      decoration: InputDecoration(
                        hintText: '账号', filled: true, fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: '密码', filled: true, fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(_tipText, style: TextStyle(color: _tipColor, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity, height: 45,
                      child: ElevatedButton(
                        onPressed: _doLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0099FF),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("登 录", style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(onPressed: () {}, child: const Text("找回密码 | 注册账号", style: TextStyle(color: Colors.grey, fontSize: 13))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 辅助组件：自定义窗口操作栏
class WindowCaptionArea extends StatelessWidget {
  const WindowCaptionArea({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32, // 窗口栏高度
      child: Stack(
        children: [
          // 这一层负责检测拖动
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) => windowManager.startDragging(),
            child: Container(),
          ),
          // 按钮层
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                iconSize: 18,
                icon: const Icon(Icons.minimize),
                onPressed: () => windowManager.minimize(),
              ),
              IconButton(
                iconSize: 18,
                icon: const Icon(Icons.close),
                onPressed: () => windowManager.close(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}