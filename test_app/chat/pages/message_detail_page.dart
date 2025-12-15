import 'package:cached_network_image/cached_network_image.dart';
import 'package:design/components/f_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:juvis/feats/home/feats/chat/domain/entities/message_detail_page_params.dart';

class MessageDetailPage extends StatelessWidget {
  const MessageDetailPage({super.key, required this.params});
  final MessageDetailPageParams? params;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      appBar: AppBar(
        title: params!.contentType == 'image'
            ? Text('${params?.userName ?? ''}의 이미지')
            : Text('${params?.userName ?? ''}의 메세지'),
      ),
      body: params!.contentType == 'image'
          ? Center(
              child: Hero(
                tag: params?.messageId ?? '', // 전달받은 메시지 ID를 heroTag로 사용
                child: CachedNetworkImage(imageUrl: params?.content ?? ''),
              ),
            )
          : SingleChildScrollView(child: Text(params?.content ?? '')),
    );
  }
}
