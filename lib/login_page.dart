import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'webrtc_mgr.dart';
import 'http_mgr.dart';
import 'register_page.dart';
import 'app_env.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final httpMgr = HttpMgr.instance();

  String _tipText = "";
  Color _tipColor = Colors.redAccent;
  bool _isLoading = false;

  // 登录并切换窗口大小
  void _doLogin() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;

    if (account.isNotEmpty && password.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _tipText = "正在登录...";
        _tipColor = Colors.blueAccent;
      });

      try {
        // 登录成功后，获取并保存 token
        // await httpMgr.login(userId: account, password: password);

        if (!mounted) return;

        setState(() {
          _tipText = "登录成功，正在进入...";
          _tipColor = Colors.green;
        });


        if (!mounted) return;

        final wtm = WebRTCManager();
        // 登录时，全局初始化信令和 WebSocket，并完成注册
        // await wtm.initializeSignaling(
        //   selfId: account,
        //   signalingUrl: kSignalingUrl,
        // );

        Navigator.pushReplacementNamed(
          context,
          '/home',
          arguments: {'selfId': account},
        );

        // 改变窗口为大尺寸
        await windowManager.setSize(const Size(1200, 800));
        await windowManager.center();
        await windowManager.setResizable(true); // 允许主页缩放
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _tipText = "登录失败: ${e.message}";
          _tipColor = Colors.redAccent;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _tipText = "登录失败，请检查网络或服务器状态";
          _tipColor = Colors.redAccent;
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      setState(() {
        _tipText = "账号和密码不能为空";
        _tipColor = Colors.redAccent;
      });
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 50,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextField(
                      controller: _accountController,
                      decoration: InputDecoration(
                        hintText: '账号',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: '密码',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          _tipText,
                          style: TextStyle(color: _tipColor, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _doLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0099FF),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                "登 录",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: (){}, 
                      child:const Text(
                        "忘记密码？",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterPage()),
                        );
                      },
                      child: const Text(
                        "注册账号",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
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
