import 'package:core/core.dart';
import 'package:core/local_storage/models/chat_room.dart';
import 'package:design/components/f_app_bar.dart';
import 'package:design/components/f_bottom_sheet.dart';
import 'package:design/components/f_scaffold.dart';
import 'package:design/components/f_toast.dart';
import 'package:design/themes/f_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // Added import
import 'package:juvis/core/router/router.dart';
import 'package:juvis/feats/auth/domain/entities/user_info_entity.dart';
import 'package:juvis/feats/home/feats/chat/domain/entities/chat_room_page_params.dart';
import 'package:juvis/feats/home/feats/chat/domain/entities/create_room_response_entity.dart';
import 'package:juvis/feats/home/feats/chat/presentation/signals/chats_signal.dart';
import 'package:juvis/feats/home/feats/chat/presentation/widgets/chatting_room_card.dart';
import 'package:juvis/injectable.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

final ChatsSignal chatsSignal = sl<ChatsSignal>();

class _ChatsPageState extends State<ChatsPage> with WidgetsBindingObserver {
  final List<SlidableController> slidableControllers = [];

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    chatsSignal.init();
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chatsSignal.disconnect();
    slidableControllers.clear();
    _closeAllSlidables();
    super.dispose();
  }

  /// 슬라이드 모두 닫기
  void _closeAllSlidables() {
    for (SlidableController controller in slidableControllers) {
      controller.close();
    }
  }

  /// 열려있는 슬라이드 있는지 여부
  bool get isExistOpenedSlidable {
    for (var controller in slidableControllers) {
      if (controller.animation.value > 0.01) {
        return true;
      }
    }
    return false;
  }

  /// 채팅방 삭제 (Dismiss action)
  void _onDismissed(ChatRoom room) async {
    FToast(message: '${room.user.name}님과의 채팅방 삭제됨').show(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        await chatsSignal.connect(true);
        if (currentRouteName == AppRoutePath.chatsPage.name) await chatsSignal.getAndSetChats();
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
        chatsSignal.disconnect();
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      appBar: FAppBar.back(context, title: 'Chats'),
      body: GestureDetector(
        onTap: _closeAllSlidables,
        child: Watch.builder(
          builder: (context) {
            final List<ChatRoom> rooms = chatsSignal.rooms.value;

            return ListView.separated(
              itemBuilder: (context, index) {
                final ChatRoom room = rooms[index];

                return ChattingRoomCard(
                  key: ValueKey(room.roomId),
                  room: room,
                  onDismissed: _onDismissed,
                  addController: (controller) => slidableControllers.add(controller),
                  onTap: () {
                    if (isExistOpenedSlidable) {
                      _closeAllSlidables();
                      return;
                    }
                    context.pushNamed(
                      AppRoutePath.chatRoomPage.name,
                      extra:
                          ChatRoomPageParams(roomId: room.roomId, userId: room.user.userId!, ctName: room.user.name!),
                    );
                  },
                );
              },
              separatorBuilder: (context, index) => Container(
                color: FColors.current.labelAlternative,
                height: 1,
                width: double.infinity,
              ),
              itemCount: rooms.length,
            );
          },
        ),
      ),
      floatingActionButton: _buildFloatingButton(),
    );
  }

  /// 채팅방 추가 버튼
  FloatingActionButton _buildFloatingButton() {
    return FloatingActionButton(
      child: const Icon(Icons.add),
      onPressed: showUserListBottomSheet,
    );
  }

  /// 유저 목록 바텀 시트
  Future<void> showUserListBottomSheet() async {
    _closeAllSlidables(); // 슬라이드 닫기

    final List<UserInfoEntity> userList = await chatsSignal.getUserList();
    if (userList.isEmpty) {
      return FToast(message: '유저 데이터 없음').show(context);
    }
    return FBottomSheet.showWithHandler(
      context,
      contentBuilder: (isExpanded) => Column(
        children: List.generate(
          userList.length,
          (index) {
            final UserInfoEntity userInfo = userList[index];
            return ListTile(
              title: Text(userInfo.name),
              leading: CircleAvatar(
                backgroundColor: Colors.accents[index % Colors.accents.length],
              ),
              onTap: () => createRoom(userInfo),
            );
          },
        ),
      ),
    );
  }

  /// 채팅방 생성
  Future<void> createRoom(UserInfoEntity userInfo) async {
    // 채팅방이 이미 존재하는지 확인
    late final ChatRoom? chatRoom;
    try {
      chatRoom = chatsSignal.rooms.value.firstWhere((e) => e.user.userId == userInfo.id);
    } catch (e) {
      chatRoom = null;
    }

    // 이미 존재하는 채팅방인 경우 바로 이동
    if (chatRoom != null) {
      // chatsSignal.clearRoomCounts(roomId: chatRoom.roomId);
      context.goNamed(
        AppRoutePath.chatRoomPage.name,
        extra: ChatRoomPageParams(
          roomId: chatRoom.roomId,
          userId: chatRoom.user.userId ?? '',
          ctName: chatRoom.user.name ?? '',
        ),
      );
      return;
    }

    final CreateRoomResponseEntity? response = await chatsSignal.createRoom(userInfo.id);
    context.pop(); // 바텀시트 닫기

    // 채팅방 생성 실패 시 채팅 목록으로 이동
    if (response == null) {
      return FToast(message: '채팅방 생성 실패').show(context);
    }

    // 채팅방으로 이동
    context.pushNamed(
      AppRoutePath.chatRoomPage.name,
      extra: ChatRoomPageParams(
        roomId: response.roomId,
        userId: response.userId,
        ctName: response.name,
      ),
    );
  }
}
