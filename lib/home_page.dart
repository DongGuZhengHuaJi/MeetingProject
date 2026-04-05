import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:intl/intl.dart';

import 'meeting_page.dart'; // 导入会议页

class HomePage extends StatelessWidget {
  final String selfId;
  const HomePage({super.key, required this.selfId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // ================= 左侧导航栏 =================
          Container(
            width: 70,
            color: const Color(0xFFF2F3F5),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // 头像
                const CircleAvatar(radius: 22, backgroundColor: Color(0xFF0052D9), child: Text("头像", style: TextStyle(color: Colors.white, fontSize: 12))),
                const SizedBox(height: 25),
                // 导航图标
                _sideIcon(Icons.videocam, "会议", isSelected: true),
                const Spacer(),
                // 底部图标
                _sideIcon(Icons.mail_outline, ""),
                _sideIcon(Icons.settings_outlined, ""),
                _sideIcon(Icons.person_outline, ""),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ================= 右侧主内容区 =================
          Expanded(
            child: Column(
              children: [
                // 顶部可拖拽栏 + 窗口控制
                _buildTopBar(),
                
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      children: [
                        // 左半部分：功能按钮
                        Expanded(flex: 5, child: _buildLeftContent(context)),
                        // 右半部分：日期与日程
                        Expanded(flex: 6, child: _buildRightContent()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 1. 顶部栏（支持拖动 + 窗口按钮）
  Widget _buildTopBar() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          // 占满剩余空间的拖动区域
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              child: Container(),
            ),
          ),
          // 最小化、最大化、关闭
          _winBtn(Icons.remove, () => windowManager.minimize()),
          _winBtn(Icons.crop_square, () async {
            if (await windowManager.isMaximized()) windowManager.unmaximize(); else windowManager.maximize();
          }),
          _winBtn(Icons.close, () => windowManager.close(), isClose: true),
        ],
      ),
    );
  }

  // 2. 左侧功能矩阵
  Widget _buildLeftContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 30,
          crossAxisSpacing: 30,
          childAspectRatio: 1.1,
          children: [
            _mainCard(context, Icons.video_call, "快速会议", const Color(0xFF0052D9), onTap: () {
              String randomRoom = (100000 + (DateTime.now().millisecondsSinceEpoch % 899999)).toString(); // 生成6位随机号
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => MeetingPage(selfId: selfId, roomId: randomRoom, isHost: true))
              );
            }),

            // 2. 加入会议：弹出对话框让用户输入房号
            _mainCard(context, Icons.group_add, "加入会议", const Color(0xFF0052D9), onTap: () {
              _showJoinDialog(context);
            }),
            
            _mainCard(context, Icons.calendar_today, "预定会议", const Color(0xFF0052D9), onTap: () {}),
            _mainCard(context, Icons.screen_share, "共享屏幕", const Color(0xFF0052D9), onTap: () {}),
          ],
        ),
      ],
    );
  }

  // 3. 右侧日期与日程
  Widget _buildRightContent() {
    String date = DateFormat('M月d日').format(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(left: 60, top: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1D2129))),
          const SizedBox(height: 5),
          const Text("Android 已登录 (未入会)", style: TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          // 暂无会议状态
          Center(
            child: Column(
              children: [
                Icon(Icons.coffee_outlined, size: 80, color: Colors.grey.withOpacity(0.2)),
                const SizedBox(height: 10),
                const Text("暂无会议", style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  // 辅助组件：侧边栏图标
  Widget _sideIcon(IconData icon, String label, {bool isSelected = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, color: isSelected ? const Color(0xFF0052D9) : Colors.black54, size: 28),
          if (label.isNotEmpty) Text(label, style: TextStyle(color: isSelected ? const Color(0xFF0052D9) : Colors.black54, fontSize: 11)),
        ],
      ),
    );
  }

  // 辅助组件：主功能卡片
// 辅助组件：主功能卡片（现在支持点击了）
  Widget _mainCard(BuildContext context, IconData icon, String title, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap, // 绑定点击回调
      borderRadius: BorderRadius.circular(18), // 保持水波纹和圆角一致
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, 
            height: 80,
            decoration: BoxDecoration(
              color: color, 
              borderRadius: BorderRadius.circular(18), 
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3), 
                  blurRadius: 10, 
                  offset: const Offset(0, 4)
                )
              ]
            ),
            child: Icon(icon, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 12),
          Text(
            title, 
            style: const TextStyle(
              fontSize: 14, 
              fontWeight: FontWeight.w500, 
              color: Color(0xFF1D2129)
            )
          ),
        ],
      ),
    );
  }
  // 辅助组件：窗口按钮
  Widget _winBtn(IconData icon, VoidCallback onTap, {bool isClose = false}) {
    return InkWell(
      onTap: onTap,
      hoverColor: isClose ? Colors.red : Colors.black12,
      child: SizedBox(width: 45, height: 40, child: Icon(icon, size: 16, color: Colors.black54)),
    );
  }

  // 辅助方法：弹窗输入房号
  void _showJoinDialog(BuildContext context) {
  TextEditingController _roomCtrl = TextEditingController();
  showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("加入会议"),
        content: TextField(controller: _roomCtrl, decoration: const InputDecoration(hintText: "请输入房间号")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          TextButton(onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => MeetingPage(selfId: selfId, roomId: _roomCtrl.text, isHost: false))
            );
          }, child: const Text("加入")),
        ],
      )
    );
  }
}