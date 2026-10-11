import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

const Color kBg = Color(0xFF090D16);
const Color kGreen = Color(0xFF22C55E);
const Color kCard = Color(0xFF111827);
const Color kBorder = Color(0xFF1F2937);

typedef Json = Map<String, dynamic>;
typedef PostDoc = DocumentSnapshot<Map<String, dynamic>>;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Koi bhi build error aaye to blank/grey screen ki jagah message dikhega.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: kBg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Something went wrong:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };

  runApp(const TalkSpikeApp());
}

class TalkSpikeApp extends StatelessWidget {
  const TalkSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TalkSpike',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        primaryColor: kGreen,
        colorScheme: const ColorScheme.dark(
          primary: kGreen,
          secondary: Color(0xFFF43F5E),
          surface: kCard,
        ),
      ),
      home: const AppGate(),
    );
  }
}

/// Firebase initialise hone tak splash dikhata hai.
/// Init fail ho to error + Retry dikhata hai (blank screen nahi).
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initFirebase();
  }

  Future<void> _initFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp().timeout(const Duration(seconds: 20));
    }
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('FCM background handler error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snapshot.hasError) {
          return _InitErrorScreen(
            error: snapshot.error.toString(),
            onRetry: () => setState(() => _initFuture = _initFirebase()),
          );
        }
        return const AuthCheckScreen();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBg,
      body: Center(child: CircularProgressIndicator(color: kGreen)),
    );
  }
}

class _InitErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _InitErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                'App start nahi ho paayi',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.black,
                ),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthCheckScreen extends StatelessWidget {
  const AuthCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: kBg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Something went wrong: ${snapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const MainScreenContainer();
        }
        return const LoginScreen();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> signOutUser() async {
  try {
    await GoogleSignIn().signOut();
  } catch (_) {}
  await FirebaseAuth.instance.signOut();
}

String timeAgo(dynamic ts) {
  if (ts is! Timestamp) return 'Just now';
  final date = ts.toDate();
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${date.day}/${date.month}/${date.year}';
}

int millisOf(dynamic ts) {
  if (ts is Timestamp) return ts.millisecondsSinceEpoch;
  return DateTime.now().millisecondsSinceEpoch; // pending server timestamp
}

List<String> asStringList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return <String>[];
}

Stream<DocumentSnapshot<Json>> userDocStream(String uid) {
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Action chalata hai aur error aaye to snackbar dikhata hai.
Future<void> runAction(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
  }
}

void openProfile(BuildContext context, String uid) {
  if (uid.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)),
  );
}

void openPost(BuildContext context, String postId) {
  if (postId.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
  );
}

String handleFromEmail(String? email) {
  if (email == null || !email.contains('@')) return '@user';
  return '@${email.split('@')[0]}';
}

String handleOf(Map<String, dynamic> u) {
  if (u['handle'] != null) return u['handle'].toString();
  return handleFromEmail(u['email']?.toString());
}

final RegExp _tagRegex = RegExp(r'(#\w+|@\w+)');

/// Post text me #hashtag aur @mention ko green dikhata hai (Twitter jaisa).
Widget richPostText(String text) {
  final spans = <InlineSpan>[];
  int last = 0;
  for (final m in _tagRegex.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(TextSpan(text: m.group(0), style: const TextStyle(color: kGreen)));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return RichText(
    text: TextSpan(
      style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.white),
      children: spans,
    ),
  );
}

Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kCard,
      title: const Text('Delete account?'),
      content: const Text(
          'Aapke posts, comments aur profile hamesha ke liye delete ho jayenge. Ye undo nahi hoga.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: kGreen)),
  );
  bool deleted = false;
  try {
    await PostService.deleteAccount();
    deleted = true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Account delete nahi hua: $e')));
  } finally {
    if (nav.mounted) {
      nav.pop(); // progress dialog
      if (deleted) nav.popUntil((r) => r.isFirst);
    }
  }
}

class TgUpload {
  final String fileId;
  final int? messageId;
  const TgUpload(this.fileId, this.messageId);
}

/// Telegram private channel ko storage ki tarah use karta hai.
/// Token/ID build time pe aate hain: --dart-define=TG_BOT_TOKEN=... --dart-define=TG_CHANNEL_ID=...
class TelegramStorage {
  // GitHub secrets (--dart-define) mile to wo use hote hain, warna neeche wale defaults.
  static const String _envToken = String.fromEnvironment('TG_BOT_TOKEN');
  static const String _envChat = String.fromEnvironment('TG_CHANNEL_ID');
  static const String _token =
      _envToken != '' ? _envToken : '8914960632:AAEbiR70JZBYXgYZ3cbxRP0Ekkv9U6wCYIo';
  static const String _chatId = _envChat != '' ? _envChat : '-1003947413983';

  static bool get isConfigured => _token.isNotEmpty && _chatId.isNotEmpty;
  static String get _api => 'https://api.telegram.org/bot$_token';

  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List>> _inflight = <String, Future<Uint8List>>{};

  // Error message me bot token kabhi user ko na dikhe.
  static String _clean(Object e) {
    var m = e.toString();
    if (_token.isNotEmpty) m = m.replaceAll(_token, '***');
    return m;
  }

  /// Image ko channel me document ki tarah bhejta hai (original quality) aur file_id return karta hai.
  static Future<TgUpload> uploadImage(
    Uint8List bytes, {
    String caption = '',
    String filename = 'image.jpg',
  }) async {
    if (!isConfigured) {
      throw 'Telegram storage set nahi hai (TG_BOT_TOKEN / TG_CHANNEL_ID)';
    }
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_api/sendDocument'))
        ..fields['chat_id'] = _chatId
        ..fields['caption'] = caption
        ..files.add(http.MultipartFile.fromBytes('document', bytes, filename: filename));
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final body = await streamed.stream.bytesToString();
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['ok'] != true) {
        final desc = decoded is Map ? decoded['description'] : body;
        throw 'Telegram error: $desc';
      }
      final result = decoded['result'];
      final doc = result is Map ? result['document'] : null;
      final id = doc is Map ? doc['file_id'] : null;
      final msgId = result is Map ? result['message_id'] : null;
      if (id == null) throw 'Telegram se file_id nahi mila';
      return TgUpload(id.toString(), msgId is int ? msgId : null);
    } catch (e) {
      throw _clean(e);
    }
  }

  static Directory? _cacheDir;

  static void _remember(String fileId, Uint8List bytes) {
    _cache[fileId] = bytes;
    if (_cache.length > 60) _cache.remove(_cache.keys.first);
  }

  static Future<File?> _diskFile(String fileId) async {
    try {
      if (_cacheDir == null) {
        final base = await getTemporaryDirectory();
        final dir = Directory('${base.path}/tg_cache');
        if (!await dir.exists()) await dir.create(recursive: true);
        _cacheDir = dir;
      }
      final safe = fileId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      return File('${_cacheDir!.path}/$safe');
    } catch (_) {
      return null;
    }
  }

  /// file_id se image bytes laata hai (memory + disk cache ke saath).
  static Future<Uint8List> fetchBytes(String fileId) {
    final cached = _cache.remove(fileId);
    if (cached != null) {
      _cache[fileId] = cached;
      return Future<Uint8List>.value(cached);
    }
    return _inflight.putIfAbsent(fileId, () async {
      try {
        final diskFile = await _diskFile(fileId);
        if (diskFile != null) {
          try {
            if (await diskFile.exists()) {
              final cachedBytes = await diskFile.readAsBytes();
              if (cachedBytes.isNotEmpty) {
                _remember(fileId, cachedBytes);
                return cachedBytes;
              }
            }
          } catch (_) {}
        }
        if (!isConfigured) throw 'Telegram storage set nahi hai';
        final meta = await http
            .get(Uri.parse('$_api/getFile?file_id=${Uri.encodeQueryComponent(fileId)}'))
            .timeout(const Duration(seconds: 20));
        final decoded = jsonDecode(meta.body);
        if (decoded is! Map || decoded['ok'] != true) {
          throw 'Telegram getFile fail: ${decoded is Map ? decoded['description'] : meta.statusCode}';
        }
        final path = (decoded['result'] as Map)['file_path'].toString();
        final file = await http
            .get(Uri.parse('https://api.telegram.org/file/bot$_token/$path'))
            .timeout(const Duration(seconds: 60));
        if (file.statusCode != 200) throw 'Image load fail (${file.statusCode})';
        final bytes = file.bodyBytes;
        _remember(fileId, bytes);
        if (diskFile != null) {
          try {
            await diskFile.writeAsBytes(bytes, flush: true);
          } catch (_) {}
        }
        return bytes;
      } catch (e) {
        throw _clean(e);
      } finally {
        _inflight.remove(fileId);
      }
    });
  }

  /// Channel se ek message (image) delete karta hai. Fail ho to ignore.
  static Future<void> deleteMessage(dynamic messageId) async {
    if (!isConfigured || messageId == null) return;
    try {
      await http.post(
        Uri.parse('$_api/deleteMessage'),
        body: {'chat_id': _chatId, 'message_id': messageId.toString()},
      ).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Text backup/log channel me bhejta hai (fail ho to ignore).
  static Future<void> log(String text) async {
    if (!isConfigured) return;
    try {
      final t = text.length > 3500 ? text.substring(0, 3500) : text;
      await http
          .post(Uri.parse('$_api/sendMessage'), body: {'chat_id': _chatId, 'text': t})
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}

Future<Uint8List?> pickImageBytes({double maxSize = 1280}) async {
  final XFile? x = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: maxSize,
    maxHeight: maxSize,
    imageQuality: 80,
  );
  if (x == null) return null;
  return x.readAsBytes();
}

class TgImage extends StatefulWidget {
  final String fileId;
  final BoxFit fit;
  final double? width;
  final double? height;
  const TgImage({
    super.key,
    required this.fileId,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  State<TgImage> createState() => _TgImageState();
}

class _TgImageState extends State<TgImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = TelegramStorage.fetchBytes(widget.fileId);
  }

  @override
  void didUpdateWidget(covariant TgImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _future = TelegramStorage.fetchBytes(widget.fileId);
    }
  }

  Widget _box(IconData? icon) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: kBorder,
      alignment: Alignment.center,
      child: icon == null
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: kGreen),
            )
          : Icon(icon, color: Colors.grey),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _box(Icons.broken_image),
          );
        }
        if (snapshot.hasError) {
          return GestureDetector(
            onTap: () => setState(
                () => _future = TelegramStorage.fetchBytes(widget.fileId)),
            child: _box(Icons.refresh),
          );
        }
        return _box(null);
      },
    );
  }
}

class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  const UserAvatar({super.key, required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    final String u = url ?? '';
    if (u.startsWith('tg:')) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: kBorder,
        child: ClipOval(
          child: TgImage(
            fileId: u.substring(3),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    final bool hasUrl = u.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: kGreen,
      backgroundImage: hasUrl ? NetworkImage(u) : null,
      onBackgroundImageError: hasUrl ? (_, __) {} : null,
      child: hasUrl ? null : Icon(Icons.person, size: radius, color: Colors.black),
    );
  }
}

/// App bar wala apna avatar (users doc se, taaki edit ki hui photo dikhe).
class MyAvatar extends StatefulWidget {
  const MyAvatar({super.key});

  @override
  State<MyAvatar> createState() => _MyAvatarState();
}

class _MyAvatarState extends State<MyAvatar> {
  Stream<DocumentSnapshot<Json>>? _stream;

  @override
  void initState() {
    super.initState();
    final me = FirebaseAuth.instance.currentUser;
    if (me != null) _stream = userDocStream(me.uid);
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (_stream == null) return UserAvatar(url: me?.photoURL, radius: 16);
    return StreamBuilder<DocumentSnapshot<Json>>(
      stream: _stream,
      builder: (context, snapshot) {
        final photo = (snapshot.data?.data()?['photoUrl'] ?? me?.photoURL)?.toString();
        return UserAvatar(url: photo, radius: 16);
      },
    );
  }
}

class ImageViewerScreen extends StatelessWidget {
  final String fileId;
  const ImageViewerScreen({super.key, required this.fileId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: TgImage(fileId: fileId, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

AppBar buildTalkSpikeAppBar(User? user) {
  return AppBar(
    backgroundColor: kBg,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    title: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: kGreen.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.bolt, color: kGreen, size: 20),
        ),
        const SizedBox(width: 8),
        const Text(
          'TalkSpike',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
        ),
      ],
    ),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: user == null ? const UserAvatar(url: null, radius: 16) : const MyAvatar(),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Firestore actions (like, repost, comment, follow, delete)
// ---------------------------------------------------------------------------

class PostService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Json> _notifCol(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  /// Apna latest naam/photo/handle (edit ke baad ka) users doc se.
  static Future<Map<String, String>> myProfile() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return {'name': 'Anonymous User', 'photo': '', 'handle': '@user'};
    Map<String, dynamic> d = <String, dynamic>{};
    try {
      d = (await _db.collection('users').doc(me.uid).get()).data() ?? <String, dynamic>{};
    } catch (_) {}
    return {
      'name': (d['name'] ?? me.displayName ?? 'Anonymous User').toString(),
      'photo': (d['photoUrl'] ?? me.photoURL ?? 'https://i.pravatar.cc/150?u=${me.uid}')
          .toString(),
      'handle': d['handle'] != null ? d['handle'].toString() : handleFromEmail(me.email),
    };
  }

  static Future<void> _notify(
    String receiverId,
    String title,
    String body, {
    String? postId,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || receiverId.isEmpty || receiverId == me.uid) return;
    try {
      await _notifCol(receiverId).add({
        'senderId': me.uid,
        'senderName': me.displayName ?? 'Someone',
        'title': title,
        'body': body,
        if (postId != null) 'postId': postId,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Notification error: $e');
    }
  }

  static Future<void> markNotificationsRead() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final snap = await _notifCol(me.uid).where('read', isEqualTo: false).limit(50).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('markNotificationsRead error: $e');
    }
  }

  static Future<void> toggleLike(
    DocumentReference<Json> ref,
    String authorId,
    bool currentlyLiked,
  ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    if (currentlyLiked) {
      await ref.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([me.uid]),
      });
    } else {
      await ref.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([me.uid]),
      });
      await _notify(
        authorId,
        'New Like',
        '${me.displayName ?? 'Someone'} liked your discussion.',
        postId: ref.id,
      );
    }
  }

  static Future<void> toggleRepost(PostDoc doc) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final data = doc.data() ?? <String, dynamic>{};
    final String origId = (data['repostOf'] ?? doc.id).toString();
    final origRef = _db.collection('posts').doc(origId);
    final repostRef = _db.collection('posts').doc('repost_${me.uid}_$origId');

    final existing = await repostRef.get();
    if (existing.exists) {
      final batch = _db.batch();
      batch.delete(repostRef);
      batch.update(origRef, {
        'reposts': FieldValue.increment(-1),
        'repostedBy': FieldValue.arrayRemove([me.uid]),
      });
      await batch.commit();
      return;
    }

    final origSnap = await origRef.get();
    if (!origSnap.exists) throw 'Original post ab available nahi hai';
    final o = origSnap.data() ?? <String, dynamic>{};

    final batch = _db.batch();
    batch.set(repostRef, {
      'authorId': o['authorId'],
      'author': o['author'],
      'handle': o['handle'],
      'authorPic': o['authorPic'],
      'content': o['content'],
      'tag': o['tag'],
      if (o['imageId'] != null) 'imageId': o['imageId'],
      'likes': 0,
      'likedBy': [],
      'comments': 0,
      'reposts': 0,
      'repostedBy': [],
      'repostOf': origId,
      'reposterId': me.uid,
      'reposterName': me.displayName ?? 'Someone',
      'timestamp': FieldValue.serverTimestamp(),
    });
    batch.update(origRef, {
      'reposts': FieldValue.increment(1),
      'repostedBy': FieldValue.arrayUnion([me.uid]),
    });
    await batch.commit();

    await _notify(
      (o['authorId'] ?? '').toString(),
      'New Repost',
      '${me.displayName ?? 'Someone'} reposted your discussion.',
      postId: origId,
    );
  }

  static Future<void> deletePost(PostDoc doc) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final data = doc.data() ?? <String, dynamic>{};

    if (data['repostOf'] != null) {
      if (data['reposterId'] != me.uid) return;
      final batch = _db.batch();
      batch.delete(doc.reference);
      batch.update(_db.collection('posts').doc(data['repostOf'].toString()), {
        'reposts': FieldValue.increment(-1),
        'repostedBy': FieldValue.arrayRemove([me.uid]),
      });
      try {
        await batch.commit();
      } catch (_) {
        // original delete ho chuka ho to sirf repost hata do
        await doc.reference.delete();
      }
      return;
    }

    if (data['authorId'] != me.uid) return;
    final comments =
        await _db.collection('comments').where('postId', isEqualTo: doc.id).get();
    // Is post ke reposts bhi hatao (warna unki image toot jaati).
    final reposts =
        await _db.collection('posts').where('repostOf', isEqualTo: doc.id).get();
    final batch = _db.batch();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    for (final r in reposts.docs) {
      batch.delete(r.reference);
    }
    batch.delete(doc.reference);
    await batch.commit();

    // Firestore se delete hone ke baad Telegram channel se image bhi hatao.
    if (data['imageMsgId'] != null) {
      await TelegramStorage.deleteMessage(data['imageMsgId']);
    }
  }

  static Future<void> addComment(String postId, String postOwnerId, String text) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final prof = await myProfile();
    final commentRef = _db.collection('comments').doc();
    final batch = _db.batch();
    batch.set(commentRef, {
      'postId': postId,
      'authorId': me.uid,
      'author': prof['name'],
      'authorPic': prof['photo'],
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('posts').doc(postId), {
      'comments': FieldValue.increment(1),
    });
    await batch.commit();

    unawaited(TelegramStorage.log('Comment by ${prof['name']} (${me.uid}) on post $postId:\n$text'));
    final String preview = text.length > 60 ? '${text.substring(0, 60)}...' : text;
    await _notify(
      postOwnerId,
      'New Comment',
      '${me.displayName ?? 'Someone'} commented: $preview',
      postId: postId,
    );
  }

  static Future<void> deleteComment(String commentId, String postId) async {
    final batch = _db.batch();
    batch.delete(_db.collection('comments').doc(commentId));
    batch.update(_db.collection('posts').doc(postId), {
      'comments': FieldValue.increment(-1),
    });
    await batch.commit();
  }

  static Future<void> toggleFollow(String targetUid, bool currentlyFollowing) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid == targetUid) return;

    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(me.uid),
      {
        'following': currentlyFollowing
            ? FieldValue.arrayRemove([targetUid])
            : FieldValue.arrayUnion([targetUid]),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection('users').doc(targetUid),
      {
        'followers': currentlyFollowing
            ? FieldValue.arrayRemove([me.uid])
            : FieldValue.arrayUnion([me.uid]),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    if (!currentlyFollowing) {
      await _notify(
        targetUid,
        'New Follower',
        '${me.displayName ?? 'Someone'} started following you.',
      );
    }
  }

  static Future<void> toggleBlock(String targetUid, bool currentlyBlocked) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid == targetUid) return;

    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(me.uid),
      {
        'blocked': currentlyBlocked
            ? FieldValue.arrayRemove([targetUid])
            : FieldValue.arrayUnion([targetUid]),
        if (!currentlyBlocked) 'following': FieldValue.arrayRemove([targetUid]),
      },
      SetOptions(merge: true),
    );
    if (!currentlyBlocked) {
      batch.set(
        _db.collection('users').doc(targetUid),
        {'followers': FieldValue.arrayRemove([me.uid])},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  static Future<void> reportPost(String postId, String reason) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    await _db.collection('reports').add({
      'postId': postId,
      'reporterId': me.uid,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Account + uska saara data (posts, comments, Telegram images) hata deta hai.
  static Future<void> deleteAccount() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final uid = me.uid;

    // 1) Identity confirm (Firebase delete ke liye recent login chahiye)
    final g = await GoogleSignIn().signIn();
    if (g == null) throw 'Cancelled';
    final ga = await g.authentication;
    await me.reauthenticateWithCredential(
      GoogleAuthProvider.credential(accessToken: ga.accessToken, idToken: ga.idToken),
    );

    final userRef = _db.collection('users').doc(uid);
    Map<String, dynamic> profile = <String, dynamic>{};
    try {
      profile = (await userRef.get()).data() ?? <String, dynamic>{};
    } catch (_) {}

    // 2) Apne posts (comments, reposts, Telegram image ke saath)
    final mine = await _db.collection('posts').where('authorId', isEqualTo: uid).get();
    for (final d in mine.docs) {
      try {
        await deletePost(d);
      } catch (e) {
        debugPrint('deleteAccount post error: $e');
      }
    }

    // 3) Apne reposts
    final myReposts = await _db.collection('posts').where('reposterId', isEqualTo: uid).get();
    for (final d in myReposts.docs) {
      try {
        await deletePost(d);
      } catch (e) {
        debugPrint('deleteAccount repost error: $e');
      }
    }

    // 4) Dusron ke posts par apne comments
    final myComments = await _db.collection('comments').where('authorId', isEqualTo: uid).get();
    for (final c in myComments.docs) {
      try {
        await deleteComment(c.id, (c.data()['postId'] ?? '').toString());
      } catch (e) {
        debugPrint('deleteAccount comment error: $e');
      }
    }

    // 5) Jinhe follow kiya tha unki followers list se hatao
    for (final other in asStringList(profile['following'])) {
      try {
        await _db.collection('users').doc(other).set(
          {'followers': FieldValue.arrayRemove([uid])},
          SetOptions(merge: true),
        );
      } catch (_) {}
    }

    // 6) Notifications, Telegram profile photo, user doc
    try {
      final notifs = await _notifCol(uid).limit(500).get();
      final batch = _db.batch();
      for (final n in notifs.docs) {
        batch.delete(n.reference);
      }
      await batch.commit();
    } catch (_) {}
    await TelegramStorage.deleteMessage(profile['photoMsgId']);
    await userRef.delete();

    // 7) Auth account
    await me.delete();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets: FollowButton, PostCard
// ---------------------------------------------------------------------------

class FollowButton extends StatefulWidget {
  final String targetUid;
  const FollowButton({super.key, required this.targetUid});

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  Stream<DocumentSnapshot<Json>>? _stream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final me = FirebaseAuth.instance.currentUser;
    if (me != null && me.uid != widget.targetUid) {
      _stream = userDocStream(me.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Json>>(
      stream: _stream,
      builder: (context, snapshot) {
        final bool following =
            asStringList(snapshot.data?.data()?['following']).contains(widget.targetUid);
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: following ? Colors.transparent : kGreen,
            foregroundColor: following ? Colors.white : Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: const Size(0, 34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: following ? Colors.grey.shade600 : kGreen),
            ),
          ),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await runAction(
                    context,
                    () => PostService.toggleFollow(widget.targetUid, following),
                  );
                  if (mounted) setState(() => _busy = false);
                },
          child: Text(
            following ? 'Following' : 'Follow',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        );
      },
    );
  }
}

class PostCard extends StatefulWidget {
  final PostDoc doc;
  final bool openOnTap;
  const PostCard({super.key, required this.doc, this.openOnTap = true});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Map<String, dynamic> _d;
  bool? _repostOverride;

  @override
  void initState() {
    super.initState();
    _d = Map<String, dynamic>.from(widget.doc.data() ?? <String, dynamic>{});
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.doc, widget.doc)) {
      _d = Map<String, dynamic>.from(widget.doc.data() ?? <String, dynamic>{});
      _repostOverride = null;
    }
  }

  bool get _isRepostDoc => _d['repostOf'] != null;

  bool _currentlyReposted(String myId) =>
      _repostOverride ??
      (asStringList(_d['repostedBy']).contains(myId) || _d['reposterId'] == myId);

  // Like turant dikhta hai (optimistic), fail ho to wapas.
  Future<void> _toggleLike() async {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (myId.isEmpty) return;
    HapticFeedback.lightImpact();

    final List<String> prevLikedBy = asStringList(_d['likedBy']);
    final int prevLikes = _d['likes'] is num ? (_d['likes'] as num).toInt() : 0;
    final bool wasLiked = prevLikedBy.contains(myId);

    setState(() {
      final next = List<String>.from(prevLikedBy);
      if (wasLiked) {
        next.remove(myId);
      } else {
        next.add(myId);
      }
      _d['likedBy'] = next;
      _d['likes'] = wasLiked ? (prevLikes > 0 ? prevLikes - 1 : 0) : prevLikes + 1;
    });

    try {
      await PostService.toggleLike(
        widget.doc.reference,
        (_d['authorId'] ?? '').toString(),
        wasLiked,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _d['likedBy'] = prevLikedBy;
        _d['likes'] = prevLikes;
      });
      showSnack(context, 'Error: $e');
    }
  }

  Future<void> _toggleRepost() async {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (myId.isEmpty) return;
    HapticFeedback.lightImpact();

    final bool was = _currentlyReposted(myId);
    final int prevReposts = _d['reposts'] is num ? (_d['reposts'] as num).toInt() : 0;

    setState(() {
      _repostOverride = !was;
      _d['reposts'] = was ? (prevReposts > 0 ? prevReposts - 1 : 0) : prevReposts + 1;
    });

    try {
      await PostService.toggleRepost(widget.doc);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _repostOverride = was;
        _d['reposts'] = prevReposts;
      });
      showSnack(context, 'Error: $e');
    }
  }

  Future<void> _onMenu(String value, String content, String authorId) async {
    switch (value) {
      case 'copy':
        {
          await Clipboard.setData(ClipboardData(text: content));
          if (mounted) showSnack(context, 'Text copy ho gaya');
          break;
        }
      case 'report':
        {
          final reason = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              backgroundColor: kCard,
              title: const Text('Report post'),
              children: ['Spam', 'Abusive or hateful', 'Misleading', 'Other']
                  .map((r) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, r),
                        child: Text(r),
                      ))
                  .toList(),
            ),
          );
          if (reason == null || !mounted) return;
          try {
            await PostService.reportPost(widget.doc.id, reason);
            if (mounted) showSnack(context, 'Report bhej di gayi. Shukriya!');
          } catch (e) {
            if (mounted) showSnack(context, 'Error: $e');
          }
          break;
        }
      case 'block':
        {
          try {
            await PostService.toggleBlock(authorId, false);
            if (mounted) {
              showSnack(context, 'User block ho gaya. Ab unke posts nahi dikhenge.');
            }
          } catch (e) {
            if (mounted) showSnack(context, 'Error: $e');
          }
          break;
        }
      case 'delete':
        {
          await runAction(context, () => PostService.deletePost(widget.doc));
          if (!widget.openOnTap && mounted) Navigator.of(context).maybePop();
          break;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isLiked = asStringList(_d['likedBy']).contains(myId);
    final bool isReposted = _currentlyReposted(myId);
    final bool isRepost = _isRepostDoc;
    final String authorId = (_d['authorId'] ?? '').toString();
    final String authorPic =
        (_d['authorPic'] ?? 'https://i.pravatar.cc/150?u=$authorId').toString();
    final String content = (_d['content'] ?? '').toString();
    final String imageId = (_d['imageId'] ?? '').toString();
    final bool canDelete = (isRepost && _d['reposterId'] == myId) ||
        (!isRepost && authorId == myId);
    final bool canModerate = authorId.isNotEmpty && authorId != myId;

    return InkWell(
      onTap: widget.openOnTap ? () => openPost(context, widget.doc.id) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kBorder, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRepost)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.repeat, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_d['reposterId'] == myId ? 'You' : (_d['reposterName'] ?? 'Someone')} reposted',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openProfile(context, authorId),
                    child: Row(
                      children: [
                        UserAvatar(url: authorPic, radius: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (_d['author'] ?? 'Anonymous').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white),
                              ),
                              Text(
                                (_d['handle'] ?? '@user').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  timeAgo(_d['timestamp']),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
                PopupMenuButton<String>(
                  color: kCard,
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 18),
                  onSelected: (value) => _onMenu(value, content, authorId),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('Copy text')),
                    if (canModerate)
                      const PopupMenuItem(value: 'report', child: Text('Report post')),
                    if (canModerate)
                      const PopupMenuItem(value: 'block', child: Text('Block user')),
                    if (canDelete)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(isRepost ? 'Undo repost' : 'Delete'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            richPostText(content),
            if (imageId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ImageViewerScreen(fileId: imageId)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 240,
                      child: TgImage(fileId: imageId, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _action(
                  const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey),
                  '${_d['comments'] ?? 0}',
                  Colors.grey.shade400,
                  () => openPost(
                      context, isRepost ? (_d['repostOf']).toString() : widget.doc.id),
                ),
                _action(
                  Icon(Icons.repeat, size: 18, color: isReposted ? kGreen : Colors.grey),
                  '${_d['reposts'] ?? 0}',
                  isReposted ? kGreen : Colors.grey.shade400,
                  _toggleRepost,
                ),
                _action(
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      key: ValueKey<bool>(isLiked),
                      size: 18,
                      color: isLiked ? Colors.redAccent : Colors.grey,
                    ),
                  ),
                  '${_d['likes'] ?? 0}',
                  isLiked ? Colors.redAccent : Colors.grey.shade400,
                  _toggleLike,
                ),
                _action(
                  const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
                  '',
                  Colors.grey,
                  () async {
                    await Clipboard.setData(ClipboardData(
                      text: '$content\n- ${_d['author'] ?? 'User'} on TalkSpike',
                    ));
                    if (mounted) {
                      showSnack(context, 'Post copy ho gaya, kahin bhi paste karke share karo');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(Widget icon, String count, Color countColor, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            icon,
            if (count.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(count, style: TextStyle(color: countColor, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // user ne cancel kiya

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCreds =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final User? user = userCreds.user;

      if (user != null) {
        // Login ho chuka hai; profile save fail ho to bhi login fail nahi dikhana.
        unawaited(_saveUserProfile(user));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login Failed: $e'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveUserProfile(User user) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      final snap = await userRef.get();
      final existing = snap.data() ?? <String, dynamic>{};
      // Edit kiya hua naam/bio overwrite na ho, isliye sirf missing fields set hote hain.
      await userRef.set({
        'uid': user.uid,
        if (existing['handle'] == null) 'handle': handleFromEmail(user.email),
        if (existing['name'] == null) 'name': user.displayName ?? 'User',
        if (existing['photoUrl'] == null)
          'photoUrl': user.photoURL ?? 'https://i.pravatar.cc/150?u=${user.uid}',
        if (existing['bio'] == null) 'bio': '',
        if (existing['createdAt'] == null)
          'createdAt': Timestamp.fromDate(user.metadata.creationTime ?? DateTime.now()),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!snap.exists) {
        unawaited(TelegramStorage.log('New user: ${user.displayName ?? 'User'} (${user.uid})'));
      }
    } catch (e) {
      debugPrint('User profile save error: $e');
    }

    try {
      await FirebaseMessaging.instance
          .requestPermission()
          .timeout(const Duration(seconds: 10));
      final String? token =
          await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 10));
      if (token != null) {
        await userRef.set({'fcmToken': token}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.bolt, size: 50, color: kGreen),
              ),
              const SizedBox(height: 16),
              const Text(
                'TalkSpike',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'A text-first community discussion platform',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              _isLoading
                  ? const CircularProgressIndicator(color: kGreen)
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 30),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main container (bottom nav)
// ---------------------------------------------------------------------------

class MainScreenContainer extends StatefulWidget {
  const MainScreenContainer({super.key});

  @override
  State<MainScreenContainer> createState() => _MainScreenContainerState();
}

class _MainScreenContainerState extends State<MainScreenContainer> {
  int _currentIndex = 0;
  final Set<int> _visited = <int>{0};
  final GlobalKey<_HomeScreenState> _homeKey = GlobalKey<_HomeScreenState>();
  Stream<QuerySnapshot<Json>>? _unreadStream;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    final me = FirebaseAuth.instance.currentUser;
    if (me != null) {
      _unreadStream = FirebaseFirestore.instance
          .collection('users')
          .doc(me.uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .limit(20)
          .snapshots();
    }
  }

  // Tab pehli baar kholne par hi bante hain (reads bachte hain).
  Widget _screenAt(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return HomeScreen(key: _homeKey);
      case 1:
        return const ExploreScreen();
      case 2:
        return const NotificationsScreen();
      default:
        return const ProfileScreen();
    }
  }

  void _select(int index) {
    if (index == 0 && _currentIndex == 0) {
      _homeKey.currentState?.scrollToTop(); // Twitter jaisa: Home dobara dabao to upar
      return;
    }
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: IndexedStack(
        index: _currentIndex,
        children: List<Widget>.generate(4, _screenAt),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: kBg,
            border: Border(top: BorderSide(color: kBorder, width: 1)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, 0),
              _buildNavItem(Icons.tag, 1),
              GestureDetector(
                onTap: () {
                  setState(() => _currentIndex = 0);
                  _homeKey.currentState?.scrollToTop();
                  _homeKey.currentState?.focusComposer();
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kGreen.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.black, size: 24),
                ),
              ),
              _buildNotificationsItem(),
              _buildNavItem(Icons.person_outline, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final bool isSelected = _currentIndex == index;
    return IconButton(
      icon: Icon(icon, color: isSelected ? kGreen : Colors.grey, size: 26),
      onPressed: () => _select(index),
    );
  }

  Widget _buildNotificationsItem() {
    final bool isSelected = _currentIndex == 2;
    final button = IconButton(
      icon: Icon(
        isSelected ? Icons.notifications : Icons.notifications_outlined,
        color: isSelected ? kGreen : Colors.grey,
        size: 26,
      ),
      onPressed: () => _select(2),
    );
    if (_unreadStream == null) return button;

    return StreamBuilder<QuerySnapshot<Json>>(
      stream: _unreadStream,
      builder: (context, snapshot) {
        final int n = snapshot.data?.docs.length ?? 0;
        // Notifications tab khula ho to unread ko read mark kar do.
        if (n > 0 && _currentIndex == 2 && !_marking) {
          _marking = true;
          PostService.markNotificationsRead().whenComplete(() => _marking = false);
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            button,
            if (n > 0 && _currentIndex != 2)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    n > 9 ? '9+' : '$n',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Home (20 posts realtime, scroll karne par aur load)
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _postController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  String _selectedTag = '#tech';
  String _feedFilter = 'All';
  bool _isPosting = false;
  Uint8List? _pickedImage;
  Set<String> _following = <String>{};
  Set<String> _blocked = <String>{};

  int _limit = 20;
  bool _hasMore = true;
  bool _loadingMore = false;
  List<QueryDocumentSnapshot<Json>> _lastDocs = <QueryDocumentSnapshot<Json>>[];
  late Stream<QuerySnapshot<Json>> _postsStream;
  StreamSubscription<DocumentSnapshot<Json>>? _meSub;

  // Filter lagne par zyada posts chahiye (filter local hota hai).
  int get _pageSize => _feedFilter == 'All' ? 20 : 100;

  Stream<QuerySnapshot<Json>> _buildStream() {
    return FirebaseFirestore.instance
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(_limit)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _limit = _pageSize;
    _postsStream = _buildStream();
    _scroll.addListener(_onScroll);

    final me = FirebaseAuth.instance.currentUser;
    if (me != null) {
      _meSub = userDocStream(me.uid).listen(
        (snap) {
          if (!mounted) return;
          setState(() {
            _following = asStringList(snap.data()?['following']).toSet();
            _blocked = asStringList(snap.data()?['blocked']).toSet();
          });
        },
        onError: (_) {},
      );
    }
  }

  @override
  void dispose() {
    _meSub?.cancel();
    _scroll.dispose();
    _postController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_hasMore || _loadingMore) return;
    if (_scroll.position.extentAfter < 700) {
      _loadingMore = true;
      setState(() {
        _limit += _pageSize;
        _postsStream = _buildStream();
      });
    }
  }

  void scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void focusComposer() {
    _composerFocus.requestFocus();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImage() async {
    if (!TelegramStorage.isConfigured) {
      _showMessage('Telegram storage set nahi hai (TG_BOT_TOKEN / TG_CHANNEL_ID secrets add karo)');
      return;
    }
    try {
      final bytes = await pickImageBytes();
      if (bytes != null && mounted) setState(() => _pickedImage = bytes);
    } catch (e) {
      _showMessage('Image pick nahi hui: $e');
    }
  }

  Future<void> _publishPost() async {
    final String text = _postController.text.trim();
    if ((text.isEmpty && _pickedImage == null) || _isPosting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isPosting = true);
    try {
      String? imageId;
      int? imageMsgId;
      final img = _pickedImage;
      if (img != null) {
        final up = await TelegramStorage.uploadImage(img, caption: 'Post image | uid: ${user.uid}');
        imageId = up.fileId;
        imageMsgId = up.messageId;
      }
      final prof = await PostService.myProfile();
      final String content = text.isEmpty ? _selectedTag : '$text $_selectedTag';
      await FirebaseFirestore.instance.collection('posts').add({
        'authorId': user.uid,
        'author': prof['name'],
        'handle': prof['handle'],
        'authorPic': prof['photo'],
        'content': content,
        'tag': _selectedTag,
        if (imageId != null) 'imageId': imageId,
        if (imageMsgId != null) 'imageMsgId': imageMsgId,
        'likes': 0,
        'likedBy': [],
        'comments': 0,
        'reposts': 0,
        'repostedBy': [],
        'timestamp': FieldValue.serverTimestamp(),
      });
      unawaited(TelegramStorage.log(
          'New post by ${prof['name']} (${user.uid})\n$content${imageId != null ? '\n[image uploaded]' : ''}'));
      _postController.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        setState(() => _pickedImage = null);
        scrollToTop();
      }
      _showMessage('Thought published successfully!');
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  bool _matchesFilter(Json d) {
    if (_blocked.contains(d['authorId']) || _blocked.contains(d['reposterId'])) return false;
    switch (_feedFilter) {
      case '#Tech':
        return d['tag'] == '#tech';
      case 'Following':
        return _following.contains(d['authorId']) || _following.contains(d['reposterId']);
      default:
        return true;
    }
  }

  void _setFilter(String filter) {
    if (filter == _feedFilter) return;
    setState(() {
      _feedFilter = filter;
      _limit = _pageSize;
      _hasMore = true;
      _loadingMore = false;
      _lastDocs = <QueryDocumentSnapshot<Json>>[];
      _postsStream = _buildStream();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: CustomScrollView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: _buildHeaderAndComposer()),
          StreamBuilder<QuerySnapshot<Json>>(
            stream: _postsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Posts load nahi ho paaye: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (snapshot.hasData) {
                _lastDocs = snapshot.data!.docs;
                if (snapshot.connectionState == ConnectionState.active) {
                  _loadingMore = false;
                  _hasMore = snapshot.data!.docs.length >= _limit && _limit < 300;
                }
              }
              if (_lastDocs.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(color: kGreen)),
                  ),
                );
              }

              final docs = _lastDocs.where((d) => _matchesFilter(d.data())).toList();

              if (docs.isEmpty) {
                String msg = 'No discussions yet. Be the first to spark one!';
                if (_feedFilter == 'Following') {
                  msg = _following.isEmpty
                      ? 'Abhi kisi ko follow nahi kiya. Explore ya kisi ke profile se follow karo.'
                      : 'Jinhe follow kiya hai unhone abhi kuch post nahi kiya.';
                }
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        msg,
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == docs.length) {
                      return _hasMore
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kGreen),
                                ),
                              ),
                            )
                          : const SizedBox(height: 40);
                    }
                    return PostCard(key: ValueKey(docs[index].id), doc: docs[index]);
                  },
                  childCount: docs.length + 1,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAndComposer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Home Feed',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Row(
                children: ['All', 'Following', '#Tech'].map((filter) {
                  final bool isActive = _feedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: GestureDetector(
                      onTap: () => _setFilter(filter),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? kGreen : kCard,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            color: isActive ? Colors.black : Colors.grey.shade400,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _postController,
                focusNode: _composerFocus,
                maxLines: 3,
                maxLength: 280,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText:
                      "What's sparking your mind today? Share thoughts, debate ideas, ask questions...",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  border: InputBorder.none,
                  counterStyle: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
              if (_pickedImage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _pickedImage!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => setState(() => _pickedImage = null),
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: [
                  IconButton(
                    tooltip: 'Photo add karo',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.image_outlined, color: kGreen),
                    onPressed: _isPosting ? null : _pickImage,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: ['#tech', '#AI', '#debate'].map((tag) {
                      final bool isSelected = _selectedTag == tag;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTag = tag),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? kGreen.withOpacity(0.2) : kBorder,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected ? kGreen : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: isSelected ? kGreen : Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: _isPosting ? null : _publishPost,
                    icon: _isPosting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.edit, size: 16),
                    label: const Text(
                      'Publish Thought',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: kBorder),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Explore (real trends + search + people)
// ---------------------------------------------------------------------------

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _loading = true;
  String? _error;
  List<QueryDocumentSnapshot<Json>> _posts = <QueryDocumentSnapshot<Json>>[];
  List<QueryDocumentSnapshot<Json>> _users = <QueryDocumentSnapshot<Json>>[];
  Set<String> _blocked = <String>{};

  static const Map<String, String> _categories = {
    '#tech': 'Technology',
    '#AI': 'Artificial Intelligence',
    '#debate': 'Debate & Opinions',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // Explore realtime nahi hai: ek baar load hota hai, neeche kheench ke refresh.
  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait<QuerySnapshot<Json>>([
        db.collection('posts').orderBy('timestamp', descending: true).limit(100).get(),
        db.collection('users').limit(40).get(),
      ]);
      Set<String> blocked = <String>{};
      final me = FirebaseAuth.instance.currentUser;
      if (me != null) {
        try {
          final doc = await db.collection('users').doc(me.uid).get();
          blocked = asStringList(doc.data()?['blocked']).toSet();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _posts = results[0].docs;
        _users = results[1].docs;
        _blocked = blocked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final String q = _query.trim().toLowerCase();
    final String myId = currentUser?.uid ?? '';

    final posts = _posts.where((d) {
      final x = d.data();
      return x['repostOf'] == null && !_blocked.contains(x['authorId']);
    }).toList();
    final users = _users.where((u) => u.id != myId && !_blocked.contains(u.id)).toList();

    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: RefreshIndicator(
        color: kGreen,
        backgroundColor: kCard,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            const Text(
              'Explore Trends',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search topics, tags, or thinkers...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: kCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_loading && _posts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: kGreen)),
              )
            else if (_error != null && _posts.isEmpty)
              Column(
                children: [
                  Text(
                    'Load nahi ho paaya: $_error',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              )
            else if (q.isEmpty)
              _buildTrending(posts, users)
            else
              _buildSearchResults(posts, users, q),
          ],
        ),
      ),
    );
  }

  Widget _buildTrending(
    List<QueryDocumentSnapshot<Json>> posts,
    List<QueryDocumentSnapshot<Json>> users,
  ) {
    final counts = <String, int>{};
    for (final d in posts) {
      final String tag = (d.data()['tag'] ?? '').toString();
      if (tag.isEmpty) continue;
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
    final trends = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trending Right Now',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        if (trends.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Abhi koi trend nahi. Pehla post karo!',
                style: TextStyle(color: Colors.grey)),
          ),
        for (final t in trends)
          _buildTrendCard(
            _categories[t.key] ?? 'Topic',
            t.key,
            '${t.value} ${t.value == 1 ? 'discussion' : 'discussions'}',
          ),
        const SizedBox(height: 16),
        const Text(
          'People to follow',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        if (users.isEmpty)
          const Text('Abhi koi aur user nahi hai.', style: TextStyle(color: Colors.grey))
        else
          ...users.take(5).map((u) => _buildUserTile(u.id, u.data())),
      ],
    );
  }

  Widget _buildSearchResults(
    List<QueryDocumentSnapshot<Json>> posts,
    List<QueryDocumentSnapshot<Json>> users,
    String q,
  ) {
    final matched = posts.where((d) {
      final x = d.data();
      final hay =
          '${x['content'] ?? ''} ${x['author'] ?? ''} ${x['handle'] ?? ''} ${x['tag'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    final people = users.where((u) {
      final x = u.data();
      return '${x['name'] ?? ''} ${handleOf(x)}'.toLowerCase().contains(q);
    }).take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (people.isNotEmpty) ...[
          const Text('People',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          ...people.map((u) => _buildUserTile(u.id, u.data())),
          const SizedBox(height: 16),
        ],
        const Text('Discussions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 8),
        if (matched.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Koi discussion nahi mili.', style: TextStyle(color: Colors.grey)),
          ),
        ...matched.map((d) => PostCard(key: ValueKey('s_${d.id}'), doc: d)),
      ],
    );
  }

  Widget _buildUserTile(String uid, Json u) {
    final String name = (u['name'] ?? 'User').toString();
    return InkWell(
      onTap: () => openProfile(context, uid),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            UserAvatar(url: (u['photoUrl'] ?? '').toString(), radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(handleOf(u),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            FollowButton(targetUid: uid),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendCard(String category, String tag, String count) {
    return GestureDetector(
      onTap: () {
        _search.text = tag;
        setState(() => _query = tag);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  tag,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(count, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
            const Icon(Icons.trending_up, color: kGreen, size: 24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Stream<QuerySnapshot<Json>>? _stream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // users/{uid}/notifications me orderBy ke liye extra index nahi chahiye.
      _stream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots();
    }
  }

  IconData _iconFor(String title) {
    switch (title) {
      case 'New Like':
        return Icons.favorite;
      case 'New Comment':
        return Icons.chat_bubble;
      case 'New Repost':
        return Icons.repeat;
      case 'New Follower':
        return Icons.person_add;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: _stream == null
          ? const Center(
              child: Text('Please login to see notifications',
                  style: TextStyle(color: Colors.grey)),
            )
          : StreamBuilder<QuerySnapshot<Json>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Notifications load nahi ho paaye: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: kGreen));
                }
                final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Json>>[];

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No notifications yet', style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final String title = (data['title'] ?? 'Notification').toString();
                    final String postId = (data['postId'] ?? '').toString();
                    final String senderId = (data['senderId'] ?? '').toString();
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (postId.isNotEmpty) {
                          openPost(context, postId);
                        } else if (senderId.isNotEmpty) {
                          openProfile(context, senderId);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: kGreen.withOpacity(0.2),
                              child: Icon(_iconFor(title), color: kGreen, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (data['body'] ?? '').toString(),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13, height: 1.3),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    timeAgo(data['timestamp']),
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class BlockMenu extends StatefulWidget {
  final String targetUid;
  const BlockMenu({super.key, required this.targetUid});

  @override
  State<BlockMenu> createState() => _BlockMenuState();
}

class _BlockMenuState extends State<BlockMenu> {
  Stream<DocumentSnapshot<Json>>? _stream;

  @override
  void initState() {
    super.initState();
    final me = FirebaseAuth.instance.currentUser;
    if (me != null && me.uid != widget.targetUid) _stream = userDocStream(me.uid);
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Json>>(
      stream: _stream,
      builder: (context, snapshot) {
        final bool blocked =
            asStringList(snapshot.data?.data()?['blocked']).contains(widget.targetUid);
        return PopupMenuButton<String>(
          color: kCard,
          icon: const Icon(Icons.more_vert, color: Colors.grey),
          onSelected: (_) => runAction(
            context,
            () => PostService.toggleBlock(widget.targetUid, blocked),
          ),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'block',
              child: Text(blocked ? 'Unblock user' : 'Block user'),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Profile (own + other users) with working tabs, follow, edit
// ---------------------------------------------------------------------------

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final String _uid;
  late final bool _isOwn;
  late final Stream<DocumentSnapshot<Json>> _userStream;
  final Map<int, Stream<QuerySnapshot<Json>>> _tabStreams = {};
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final me = FirebaseAuth.instance.currentUser;
    _uid = widget.userId ?? me?.uid ?? '';
    _isOwn = me != null && me.uid == _uid;
    _userStream = userDocStream(_uid);
  }

  Stream<QuerySnapshot<Json>> _streamFor(int tab) {
    final db = FirebaseFirestore.instance;
    return _tabStreams.putIfAbsent(tab, () {
      switch (tab) {
        case 1:
          return db.collection('comments').where('authorId', isEqualTo: _uid).limit(100).snapshots();
        case 2:
          return db.collection('posts').where('likedBy', arrayContains: _uid).limit(100).snapshots();
        default:
          return db.collection('posts').where('authorId', isEqualTo: _uid).limit(100).snapshots();
      }
    });
  }

  String _joinedText(Json data) {
    DateTime? d;
    final created = data['createdAt'];
    if (created is Timestamp) d = created.toDate();
    d ??= _isOwn ? FirebaseAuth.instance.currentUser?.metadata.creationTime : null;
    if (d == null) return 'Joined recently';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return 'Joined ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _showEditSheet(String name, String bio, String? photo) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EditProfileSheet(initialName: name, initialBio: bio, initialPhoto: photo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot<Json>>(
      stream: _userStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final String name = (data['name'] ?? (_isOwn ? me?.displayName : null) ?? 'User').toString();
        final String? photo =
            (data['photoUrl'] ?? (_isOwn ? me?.photoURL : null))?.toString();
        final String handle = data['handle'] != null
            ? data['handle'].toString()
            : handleFromEmail((data['email'] ?? (_isOwn ? me?.email : null))?.toString());
        final String bio = (data['bio'] ?? '').toString();
        final int followers = asStringList(data['followers']).length;
        final int following = asStringList(data['following']).length;

        return Scaffold(
          backgroundColor: kBg,
          appBar: AppBar(
            title: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
            backgroundColor: kBg,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            actions: [
              if (_isOwn)
                PopupMenuButton<String>(
                  color: kCard,
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onSelected: (v) async {
                    if (v == 'logout') {
                      // Agar ye profile push hua tha to pehle wapas aao.
                      final nav = Navigator.of(context);
                      if (nav.canPop()) nav.popUntil((r) => r.isFirst);
                      await signOutUser();
                    } else if (v == 'delete') {
                      await confirmAndDeleteAccount(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'logout', child: Text('Logout')),
                    PopupMenuItem(value: 'delete', child: Text('Delete account')),
                  ],
                )
              else
                BlockMenu(targetUid: _uid),
              const SizedBox(width: 4),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 120,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green, Colors.indigo, Colors.purple],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Transform.translate(
                            offset: const Offset(0, -35),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration:
                                      const BoxDecoration(color: kBg, shape: BoxShape.circle),
                                  child: UserAvatar(url: photo, radius: 38),
                                ),
                                if (_isOwn)
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(color: Colors.grey.shade600),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20)),
                                    ),
                                    onPressed: () => _showEditSheet(name, bio, photo),
                                    child: const Text('Edit Profile',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 13)),
                                  )
                                else
                                  FollowButton(targetUid: _uid),
                              ],
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  handle,
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  bio.isEmpty
                                      ? (_isOwn
                                          ? 'Bio add karne ke liye Edit Profile dabao.'
                                          : 'Is user ne abhi bio nahi likhi.')
                                      : bio,
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: bio.isEmpty ? Colors.grey : Colors.white70),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 16,
                                  runSpacing: 6,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today,
                                            size: 14, color: Colors.grey.shade500),
                                        const SizedBox(width: 4),
                                        Text(_joinedText(data),
                                            style: TextStyle(
                                                color: Colors.grey.shade500, fontSize: 12)),
                                      ],
                                    ),
                                    _countText('$following', 'Following'),
                                    _countText('$followers', 'Followers'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: kBorder, height: 1),
                    Row(
                      children: [
                        TabItem(
                            title: 'Discussions',
                            isActive: _tab == 0,
                            onTap: () => setState(() => _tab = 0)),
                        TabItem(
                            title: 'Replies',
                            isActive: _tab == 1,
                            onTap: () => setState(() => _tab = 1)),
                        TabItem(
                            title: 'Likes',
                            isActive: _tab == 2,
                            onTap: () => setState(() => _tab = 2)),
                      ],
                    ),
                    const Divider(color: kBorder, height: 1),
                  ],
                ),
              ),
              _buildTabContent(),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _countText(String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      ],
    );
  }

  Widget _buildTabContent() {
    final int tab = _tab;
    return StreamBuilder<QuerySnapshot<Json>>(
      stream: _streamFor(tab),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Load nahi ho paaya: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: kGreen)),
            ),
          );
        }

        var list = (snapshot.data?.docs ?? <QueryDocumentSnapshot<Json>>[]).toList();
        if (tab == 0) {
          list = list.where((d) => d.data()['repostOf'] == null).toList();
        }
        list.sort((a, b) =>
            millisOf(b.data()['timestamp']).compareTo(millisOf(a.data()['timestamp'])));

        if (list.isEmpty) {
          const messages = [
            'Abhi koi discussion nahi.',
            'Abhi koi reply nahi.',
            'Abhi kuch like nahi kiya.',
          ];
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(messages[tab], style: const TextStyle(color: Colors.grey)),
              ),
            ),
          );
        }

        if (tab == 1) {
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final c = list[index].data();
                return InkWell(
                  onTap: () => openPost(context, (c['postId'] ?? '').toString()),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: kBorder, width: 1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Replied  -  ${timeAgo(c['timestamp'])}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                        const SizedBox(height: 6),
                        Text((c['text'] ?? '').toString(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14, height: 1.4)),
                      ],
                    ),
                  ),
                );
              },
              childCount: list.length,
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) =>
                PostCard(key: ValueKey('p${tab}_${list[index].id}'), doc: list[index]),
            childCount: list.length,
          ),
        );
      },
    );
  }
}

class EditProfileSheet extends StatefulWidget {
  final String initialName;
  final String initialBio;
  final String? initialPhoto;
  const EditProfileSheet({
    super.key,
    required this.initialName,
    required this.initialBio,
    this.initialPhoto,
  });

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  late final TextEditingController _bio = TextEditingController(text: widget.initialBio);
  Uint8List? _newPhoto;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (!TelegramStorage.isConfigured) {
      setState(() => _error = 'Telegram storage set nahi hai (TG_BOT_TOKEN / TG_CHANNEL_ID)');
      return;
    }
    try {
      final bytes = await pickImageBytes(maxSize: 512);
      if (bytes != null && mounted) {
        setState(() {
          _newPhoto = bytes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Photo pick nahi hui: $e');
    }
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    final String bio = _bio.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Naam khali nahi ho sakta');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final update = <String, dynamic>{
        'name': name,
        'bio': bio,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_newPhoto != null) {
        final up = await TelegramStorage.uploadImage(
          _newPhoto!,
          caption: 'Profile photo | uid: ${user.uid}',
        );
        update['photoUrl'] = 'tg:${up.fileId}';
        if (up.messageId != null) update['photoMsgId'] = up.messageId;
      }
      await user.updateDisplayName(name);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(update, SetOptions(merge: true));
      unawaited(TelegramStorage.log('Profile updated: $name (${user.uid})'));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Save nahi hua: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Profile',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: _saving ? null : _pickPhoto,
                child: Stack(
                  children: [
                    _newPhoto != null
                        ? CircleAvatar(radius: 40, backgroundImage: MemoryImage(_newPhoto!))
                        : UserAvatar(url: widget.initialPhoto, radius: 40),
                    const Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: kGreen,
                        child: Icon(Icons.camera_alt, size: 15, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              maxLength: 30,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _bio,
              maxLength: 160,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Bio'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TabItem extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;
  const TabItem({super.key, required this.title, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: isActive ? kGreen : Colors.transparent, width: 2),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? kGreen : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Post detail + comments
// ---------------------------------------------------------------------------

class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _comment = TextEditingController();
  bool _sending = false;
  String _postOwnerId = '';

  late final Stream<DocumentSnapshot<Json>> _postStream;
  late final Stream<QuerySnapshot<Json>> _commentsStream;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _postStream = db.collection('posts').doc(widget.postId).snapshots();
    _commentsStream =
        db.collection('comments').where('postId', isEqualTo: widget.postId).snapshots();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await runAction(context, () => PostService.addComment(widget.postId, _postOwnerId, text));
    if (!mounted) return;
    _comment.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Discussion',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Json>>(
              stream: _postStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Load nahi ho paaya: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: kGreen));
                }
                final doc = snapshot.data!;
                if (!doc.exists) {
                  return const Center(
                    child: Text('Ye post ab available nahi hai.',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                _postOwnerId = (doc.data()?['authorId'] ?? '').toString();

                return ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    PostCard(doc: doc, openOnTap: false),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Comments',
                        style: TextStyle(
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ),
                    StreamBuilder<QuerySnapshot<Json>>(
                      stream: _commentsStream,
                      builder: (context, cSnap) {
                        if (cSnap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Comments load nahi hue: ${cSnap.error}',
                                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          );
                        }
                        if (!cSnap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator(color: kGreen)),
                          );
                        }
                        final comments = cSnap.data!.docs.toList()
                          ..sort((a, b) => millisOf(a.data()['timestamp'])
                              .compareTo(millisOf(b.data()['timestamp'])));
                        if (comments.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text('Abhi koi comment nahi. Pehla comment karo!',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          );
                        }
                        return Column(
                          children: comments.map((c) {
                            final x = c.data();
                            final String authorId = (x['authorId'] ?? '').toString();
                            return Container(
                              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: kBorder, width: 1)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => openProfile(context, authorId),
                                    child: UserAvatar(
                                        url: (x['authorPic'] ?? '').toString(), radius: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                (x['author'] ?? 'User').toString(),
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(timeAgo(x['timestamp']),
                                                style: TextStyle(
                                                    color: Colors.grey.shade600, fontSize: 11)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text((x['text'] ?? '').toString(),
                                            style: const TextStyle(
                                                color: Colors.white70, fontSize: 13, height: 1.3)),
                                      ],
                                    ),
                                  ),
                                  if (authorId == myId)
                                    IconButton(
                                      iconSize: 18,
                                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                      onPressed: () => runAction(
                                        context,
                                        () => PostService.deleteComment(c.id, widget.postId),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                color: kBg,
                border: Border(top: BorderSide(color: kBorder, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 280,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Apna comment likho...',
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                        counterText: '',
                        filled: true,
                        fillColor: kCard,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: kGreen),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send, color: kGreen),
                          onPressed: _send,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
