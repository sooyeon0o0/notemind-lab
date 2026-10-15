import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../main.dart' show green, ink;
import '../core/config.dart';
import '../core/document_import.dart';
import '../data/inference.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'controllers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int tab = widget.initialTab;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: tab,
      children: [
        DocumentsScreen(
          onAsk: (doc) {
            ref.read(chatProvider.notifier).newChat(documentId: doc?.id);
            setState(() => tab = 1);
          },
        ),
        const ChatScreen(),
        const SettingsScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (index) => setState(() => tab = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: '문서함',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
          label: '질문하기',
        ),
        NavigationDestination(icon: Icon(Icons.tune_rounded), label: '연결 설정'),
      ],
    ),
  );
}

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key, required this.onAsk});
  final void Function(NoteDocument?) onAsk;
  Future<void> pick(BuildContext context, WidgetRef ref) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: documentExtensions,
      );
      if (file == null || !context.mounted) {
        return;
      }
      final length = await file.length();
      if (length != null) validateDocumentFile(file.name, length);
      final bytes = await file.readAsBytes();
      if (!context.mounted) {
        return;
      }
      await ref.read(uploadProvider.notifier).upload(file.name, bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider),
        upload = ref.watch(uploadProvider);
    final chatBusy = ref.watch(chatProvider.select((s) => s.busy));
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(documentsProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.auto_stories_rounded,
                          color: green,
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'NoteMind',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Spacer(),
                        Tag('MY STUDY SPACE'),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Text(
                      '오늘의 배움,\n차곡차곡.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '노트를 올리면, 질문할 준비가 끝나요.',
                      style: TextStyle(color: Color(0xff68766d)),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: green,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.library_books_outlined,
                                color: Color(0xffd7e9b9),
                              ),
                              SizedBox(width: 10),
                              Text(
                                '나만의 지식 서랍',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '강의노트 한 장에서 시작해 보세요.\n답변의 근거까지 함께 찾아드려요.',
                            style: TextStyle(
                              color: Color(0xffd6e3d7),
                              height: 1.65,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const Key('upload-file'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xffe4efc7),
                                foregroundColor: ink,
                              ),
                              onPressed: upload.busy
                                  ? null
                                  : () => pick(context, ref),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('노트 업로드'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Center(
                            child: Text(
                              'PDF 최대 20MB · TXT/MD 최대 1MB',
                              style: TextStyle(
                                color: Color(0xffc5d6c9),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (upload.busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: upload.progress,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            const SizedBox(height: 8),
                            Text(upload.label),
                          ],
                        ),
                      ),
                    if (upload.error != null) ErrorPanel(upload.error!),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(
                          '내 문서',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 8),
                        if (docs.hasValue) Tag('${docs.value!.length}'),
                        const Spacer(),
                        IconButton(
                          tooltip: '문서 새로고침',
                          onPressed: () => ref.invalidate(documentsProvider),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            ...docs.when(
              data: (items) => items.isEmpty
                  ? [
                      const SliverToBoxAdapter(
                        child: EmptyPanel(
                          icon: Icons.note_add_outlined,
                          title: '아직 비어 있는 문서함',
                          body: '첫 강의노트를 올려보세요.\n준비가 끝난 문서로 질문할 수 있어요.',
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final doc = items[i];
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xffe0e5db),
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  8,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xffedf1e5),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.description_outlined,
                                            color: green,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                doc.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                doc.status == 'ready'
                                                    ? '검색 준비 완료 · ${doc.chunkCount}개 청크'
                                                    : doc.status == 'failed'
                                                    ? '처리 실패 · 다시 시도할 수 있어요'
                                                    : '처리 중 · 중단됐다면 다시 시도',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: doc.status == 'failed'
                                                      ? Colors.deepOrange
                                                      : green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          enabled: !upload.busy && !chatBusy,
                                          tooltip: '문서 메뉴',
                                          onSelected: (action) async {
                                            if (action == 'retry') {
                                              await ref
                                                  .read(uploadProvider.notifier)
                                                  .retry(doc);
                                            } else {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) =>
                                                        AlertDialog(
                                                          title: const Text(
                                                            '문서를 삭제할까요?',
                                                          ),
                                                          content: Text(
                                                            '${doc.title}\n원본 파일과 검색 청크가 삭제됩니다.',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                '취소',
                                                              ),
                                                            ),
                                                            FilledButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                '삭제',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                  );
                                              if (confirmed != true) {
                                                return;
                                              }
                                              try {
                                                await ref
                                                    .read(repositoryProvider)
                                                    .removeDocument(doc);
                                                ref.invalidate(
                                                  documentsProvider,
                                                );
                                              } catch (e) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            friendlyError(e),
                                                          ),
                                                        ),
                                                      );
                                                }
                                              }
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            if (doc.status != 'ready')
                                              const PopupMenuItem(
                                                value: 'retry',
                                                child: Text('처리 다시 시도'),
                                              ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text('문서 삭제'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (doc.error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          doc.error!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.deepOrange,
                                          ),
                                        ),
                                      ),
                                    if (doc.status == 'ready')
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: chatBusy
                                              ? null
                                              : () => onAsk(doc),
                                          icon: const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 17,
                                          ),
                                          label: const Text('이 노트에 질문하기'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorPanel(
                      friendlyError(e),
                      onRetry: () => ref.invalidate(documentsProvider),
                    ),
                  ),
                ),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final input = TextEditingController(), scroll = ScrollController();
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) {
      return;
    }
    input.clear();
    ref.read(chatProvider.notifier).send(text);
  }

  Future<void> history() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final list = ref.watch(conversationsProvider);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '지난 대화',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: list.when(
                      data: (items) => items.isEmpty
                          ? const EmptyPanel(
                              icon: Icons.forum_outlined,
                              title: '저장된 대화가 없어요',
                              body: '첫 질문을 보내면 여기에 남아요.',
                            )
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, i) => ListTile(
                                leading: Icon(
                                  items[i]['mode'] == 'rag'
                                      ? Icons.library_books_outlined
                                      : Icons.chat_outlined,
                                ),
                                title: Text(
                                  items[i]['title'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.pop(context);
                                  ref
                                      .read(chatProvider.notifier)
                                      .open(items[i]);
                                },
                              ),
                            ),
                      error: (e, _) => ErrorPanel(
                        friendlyError(e),
                        onRetry: () => ref.invalidate(conversationsProvider),
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    ref.listen(chatProvider, (before, after) {
      if (before?.messages != after.messages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients &&
              (scroll.position.maxScrollExtent - scroll.offset < 250 ||
                  before?.messages.length != after.messages.length)) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
          }
        });
      }
    });
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 12, 6),
            child: Row(
              children: [
                const Text(
                  '질문하기',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '지난 대화',
                  onPressed: chat.busy ? null : history,
                  icon: const Icon(Icons.history_rounded),
                ),
                IconButton(
                  tooltip: '새 대화',
                  onPressed: chat.busy
                      ? null
                      : () => ref.read(chatProvider.notifier).newChat(),
                  icon: const Icon(Icons.edit_square),
                ),
              ],
            ),
          ),
          if (chat.documentId != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Tag('선택한 문서'),
            ),
          Expanded(
            child: chat.messages.isEmpty
                ? SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.all(25),
                            decoration: const BoxDecoration(
                              color: Color(0xffe7edde),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.question_answer_outlined,
                              size: 42,
                              color: green,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '노트와 대화해 보세요',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '내 자료에서 먼저 답을 찾아요.\n근거가 없으면 일반 지식으로 답변받을 수 있어요.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xff6b786f)),
                          ),
                          const SizedBox(height: 30),
                          for (final text in [
                            '이 자료의 핵심 내용을 설명해줘',
                            '중요한 개념을 예시와 함께 알려줘',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: OutlinedButton(
                                onPressed: () {
                                  input.text = text;
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50),
                                  side: const BorderSide(
                                    color: Color(0xffd8e0d2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        text,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.north_west_rounded,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, i) => MessageBubble(
                      message: chat.messages[i],
                      active: chat.busy && i == chat.messages.length - 1,
                      onGeneralAnswer:
                          !chat.busy &&
                              i == chat.messages.length - 1 &&
                              chat.messages[i].canAnswerGenerally
                          ? () => ref
                                .read(chatProvider.notifier)
                                .answerFromGeneralKnowledge()
                          : null,
                      onRegenerate:
                          !chat.busy &&
                              i == chat.messages.length - 1 &&
                              chat.messages[i].role == 'assistant'
                          ? () => ref.read(chatProvider.notifier).regenerate()
                          : null,
                    ),
                  ),
          ),
          if (chat.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ErrorPanel(
                chat.error!,
                onRetry: chat.error!.contains('이력')
                    ? () => ref.read(chatProvider.notifier).saveHistory()
                    : null,
                retryLabel: '이력 저장 재시도',
              ),
            ),
          if (chat.busy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      chat.phase,
                      style: const TextStyle(fontSize: 12, color: green),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('question'),
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      hintText: '궁금한 내용을 질문해 보세요…',
                      counterText: '',
                    ),
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('send-stop'),
                  tooltip: chat.busy ? '생성 중단' : '질문 보내기',
                  onPressed: chat.busy
                      ? () => ref.read(chatProvider.notifier).stop()
                      : send,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: Icon(
                    chat.busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.active = false,
    this.onRegenerate,
    this.onGeneralAnswer,
  });
  final ChatMessage message;
  final bool active;
  final VoidCallback? onRegenerate, onGeneralAnswer;
  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: user
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (onRegenerate != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('다시 답변', style: TextStyle(fontSize: 12)),
              ),
            ),
          if (!user)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.auto_stories_rounded, size: 17, color: green),
                  SizedBox(width: 7),
                  Text(
                    'NoteMind',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
                ],
              ),
            ),
          if (!user && message.answerKind == 'general')
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '일반 지식 답변 · 업로드한 자료에 근거하지 않은 답변',
                style: TextStyle(fontSize: 12, color: Color(0xff806124)),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 540),
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: user ? const Color(0xffe3ebdc) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: user ? null : Border.all(color: const Color(0xffe5e9df)),
            ),
            child: SelectableText(
              message.content.isEmpty
                  ? (active
                        ? '답변을 준비하고 있어요…'
                        : message.status == 'stopped'
                        ? '응답이 중단되었습니다.'
                        : '응답을 받지 못했습니다.')
                  : message.content,
              style: const TextStyle(fontSize: 15, height: 1.7),
            ),
          ),
          if (onGeneralAnswer != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                key: const Key('general-answer'),
                onPressed: onGeneralAnswer,
                icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                label: const Text('일반 지식으로 답변받기'),
              ),
            ),
          if (message.status == 'stopped' || message.status == 'error')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                message.status == 'stopped' ? '중단된 응답' : '완료되지 않은 응답',
                style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
              ),
            ),
          if (message.sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.sources
                    .asMap()
                    .entries
                    .map(
                      (entry) => ActionChip(
                        avatar: const Icon(Icons.article_outlined, size: 15),
                        label: Text(
                          '[${entry.key + 1}] ${entry.value.title}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (context) => SafeArea(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    entry.value.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.value.similarity == null
                                        ? '문서에서 직접 가져온 근거'
                                        : '청크 ${entry.value.position + 1} · 검색 유사도 ${(entry.value.similarity! * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      color: green,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  SelectableText(
                                    entry.value.content,
                                    style: const TextStyle(height: 1.8),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    '검색된 원문입니다. 답변이 실제로 이 내용을 근거로 하는지 확인하세요.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xff738074),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController supabaseUrl,
      anonKey,
      chatUrl,
      embeddingUrl,
      model,
      embeddingModel,
      keyField;
  String? result;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final c = ref.read(configProvider);
    supabaseUrl = TextEditingController(text: c.supabaseUrl);
    anonKey = TextEditingController(text: c.anonKey);
    if (c.anonKey.isEmpty) {
      result = 'Supabase 공개 키를 입력하고 설정 저장을 누르세요.';
    }
    chatUrl = TextEditingController(text: c.chatUrl);
    embeddingUrl = TextEditingController(text: c.embeddingUrl);
    model = TextEditingController(text: c.model);
    embeddingModel = TextEditingController(text: c.embeddingModel);
    keyField = TextEditingController(text: c.apiKey);
  }

  @override
  void dispose() {
    for (final c in [
      supabaseUrl,
      anonKey,
      chatUrl,
      embeddingUrl,
      model,
      embeddingModel,
      keyField,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  AppConfig get config => AppConfig(
    supabaseUrl: supabaseUrl.text.trim(),
    anonKey: anonKey.text.trim(),
    chatUrl: chatUrl.text.trim(),
    embeddingUrl: embeddingUrl.text.trim(),
    model: model.text.trim(),
    embeddingModel: embeddingModel.text.trim(),
    apiKey: keyField.text.trim(),
  );
  Future<void> save() async {
    setState(() => busy = true);
    try {
      await ref.read(configProvider.notifier).save(config);
      if (mounted) {
        setState(() => result = '설정을 저장했습니다.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => result = friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> probe() async {
    setState(() {
      busy = true;
      result = '서버 응답 확인 중…';
    });
    final session = InferenceSession(config);
    final results = <String>[];
    try {
      await checkSupabase(config);
      final saved = ref.read(configProvider);
      if (saved.supabaseUrl == config.supabaseUrl &&
          saved.anonKey == config.anonKey) {
        await ref.read(repositoryProvider).documents();
        results.add('Supabase · 연결됨');
      } else {
        results.add('Supabase · 연결됨 (설정 저장 후 적용)');
      }
    } catch (e) {
      results.add('Supabase · ${friendlyError(e)}');
    }
    try {
      await session.probe(config.chatUrl, config.model);
      results.add('생성 모델 · 연결됨');
    } catch (e) {
      results.add('생성 모델 · ${friendlyError(e)}');
    }
    try {
      await session.probe(config.embeddingUrl, config.embeddingModel);
      results.add('임베딩 모델 · 연결됨');
    } catch (e) {
      results.add('임베딩 모델 · ${friendlyError(e)}');
    }
    session.close();
    if (mounted) {
      setState(() {
        busy = false;
        result = results.join('\n');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final working =
        ref.watch(chatProvider.select((s) => s.busy)) ||
        ref.watch(uploadProvider.select((s) => s.busy));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('연결 설정', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            '내 PC의 서버와 연결합니다.',
            style: TextStyle(color: Color(0xff6b786f)),
          ),
          const SizedBox(height: 24),
          const Tag('SUPABASE'),
          const SizedBox(height: 10),
          TextField(
            controller: supabaseUrl,
            decoration: const InputDecoration(labelText: 'Supabase 주소'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: anonKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Supabase 공개 키 (anon key)',
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'docker/supabase/.env의 ANON_KEY 값입니다.',
            style: TextStyle(fontSize: 12, color: Color(0xff6b786f)),
          ),
          const SizedBox(height: 24),
          const Text('생성 서버', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: chatUrl,
            decoration: const InputDecoration(labelText: 'API 주소 (/v1 포함)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: model,
            decoration: const InputDecoration(labelText: '생성 모델 ID'),
          ),
          const SizedBox(height: 24),
          const Text('임베딩 서버', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: embeddingUrl,
            decoration: const InputDecoration(labelText: '임베딩 API 주소'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: embeddingModel,
            decoration: const InputDecoration(labelText: '임베딩 모델 ID'),
          ),
          const SizedBox(height: 10),
          const Text(
            '1024차원 모델을 사용하세요. 모델을 바꾸면 기존 문서를 다시 업로드해야 합니다.',
            style: TextStyle(fontSize: 12, color: Color(0xff6b786f)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: keyField,
            obscureText: true,
            decoration: const InputDecoration(labelText: '로컬 추론 API 키'),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy || working ? null : save,
                  child: const Text('설정 저장'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || working ? null : probe,
                  child: const Text('연결 확인'),
                ),
              ),
            ],
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(result!),
            ),
          const SizedBox(height: 32),
          const Text(
            'NoteMind · 캠퍼스 노트 어시스턴트\nFlutter × Supabase × vLLM',
            style: TextStyle(fontSize: 12, color: Color(0xff819083)),
          ),
        ],
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xffe8eedf),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: green,
        letterSpacing: .5,
      ),
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(
    this.message, {
    super.key,
    this.onRetry,
    this.retryLabel = '다시 시도',
  });
  final String message, retryLabel;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xffffeee5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: const TextStyle(color: Color(0xff944c2d), fontSize: 13),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
      ],
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 36, color: const Color(0xff899c82)),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff7b877d),
            fontSize: 13,
            height: 1.7,
          ),
        ),
      ],
    ),
  );
}
