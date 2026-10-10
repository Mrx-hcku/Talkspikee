import 'dart:async';
import 'dart:convert';
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

/// Telegram private channel ko storage ki tarah use karta hai.
/// Token/ID build time pe aate hain: --dart-define=TG_BOT_TOKEN=... --dart-define=TG_CHANNEL_ID=...
class TelegramStorage {
  static const String _token = String.fromEnvironment('TG_BOT_TOKEN');
  static const String _chatId = String.fromEnvironment('TG_CHANNEL_ID');

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
  static Future<String> uploadImage(
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
      if (id == null) throw 'Telegram se file_id nahi mila';
      return id.toString();
    } catch (e) {
      throw _clean(e);
    }
  }

  /// file_id se image bytes laata hai (memory cache ke saath).
  static Future<Uint8List> fetchBytes(String fileId) {
    final cached = _cache.remove(fileId);
    if (cached != null) {
      _cache[fileId] = cached;
      return Future<Uint8List>.value(cached);
    }
    return _inflight.putIfAbsent(fileId, () async {
      try {
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
        _cache[fileId] = bytes;
        if (_cache.length > 60) _cache.remove(_cache.keys.first);
        return bytes;
      } catch (e) {
        throw _clean(e);
      } finally {
        _inflight.remove(fileId);
      }
    });
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
      const Icon(Icons.dark_mode_outlined, color: Colors.grey),
      const SizedBox(width: 16),
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

  /// Apna latest naam/photo (edit ke baad ka) users doc se.
  static Future<Map<String, String>> myProfile() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return {'name': 'Anonymous User', 'photo': ''};
    Map<String, dynamic> d = <String, dynamic>{};
    try {
      d = (await _db.collection('users').doc(me.uid).get()).data() ?? <String, dynamic>{};
    } catch (_) {}
    return {
      'name': (d['name'] ?? me.displayName ?? 'Anonymous User').toString(),
      'photo': (d['photoUrl'] ?? me.photoURL ?? 'https://i.pravatar.cc/150?u=${me.uid}')
          .toString(),
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
      await _db.collection('notifications').add({
        'receiverId': receiverId,
        'senderId': me.uid,
        'senderName': me.displayName ?? 'Someone',
        'title': title,
        'body': body,
        if (postId != null) 'postId': postId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Notification error: $e');
    }
  }

  static Future<void> toggleLike(PostDoc doc) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final data = doc.data() ?? <String, dynamic>{};
    final bool isLiked = asStringList(data['likedBy']).contains(me.uid);

    if (isLiked) {
      await doc.reference.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([me.uid]),
      });
    } else {
      await doc.reference.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([me.uid]),
      });
      await _notify(
        (data['authorId'] ?? '').toString(),
        'New Like',
        '${me.displayName ?? 'Someone'} liked your discussion.',
        postId: doc.id,
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
    final batch = _db.batch();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    batch.delete(doc.reference);
    await batch.commit();
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

class PostCard extends StatelessWidget {
  final PostDoc doc;
  final bool openOnTap;
  const PostCard({super.key, required this.doc, this.openOnTap = true});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() ?? <String, dynamic>{};
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isLiked = asStringList(data['likedBy']).contains(myId);
    final bool isRepost = data['repostOf'] != null;
    final bool isReposted =
        asStringList(data['repostedBy']).contains(myId) || data['reposterId'] == myId;
    final String authorId = (data['authorId'] ?? '').toString();
    final String authorPic =
        (data['authorPic'] ?? 'https://i.pravatar.cc/150?u=$authorId').toString();
    final String content = (data['content'] ?? '').toString();
    final String imageId = (data['imageId'] ?? '').toString();
    final bool canDelete =
        (isRepost && data['reposterId'] == myId) || (!isRepost && authorId == myId);

    return InkWell(
      onTap: openOnTap ? () => openPost(context, doc.id) : null,
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
                        '${data['reposterId'] == myId ? 'You' : (data['reposterName'] ?? 'Someone')} reposted',
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
                                (data['author'] ?? 'Anonymous').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white),
                              ),
                              Text(
                                (data['handle'] ?? '@user').toString(),
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
                  timeAgo(data['timestamp']),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
                PopupMenuButton<String>(
                  color: kCard,
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 18),
                  onSelected: (value) async {
                    if (value == 'copy') {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (context.mounted) showSnack(context, 'Text copy ho gaya');
                    } else if (value == 'delete') {
                      await runAction(context, () => PostService.deletePost(doc));
                      if (!openOnTap && context.mounted) {
                        Navigator.of(context).maybePop();
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('Copy text')),
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
            Text(
              content,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white),
            ),
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
                  Icons.chat_bubble_outline,
                  '${data['comments'] ?? 0}',
                  Colors.grey,
                  () => openPost(context, isRepost ? (data['repostOf']).toString() : doc.id),
                ),
                _action(
                  Icons.repeat,
                  '${data['reposts'] ?? 0}',
                  isReposted ? kGreen : Colors.grey,
                  () => runAction(context, () => PostService.toggleRepost(doc)),
                ),
                _action(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  '${data['likes'] ?? 0}',
                  isLiked ? Colors.redAccent : Colors.grey,
                  () => runAction(context, () => PostService.toggleLike(doc)),
                ),
                _action(
                  Icons.share_outlined,
                  '',
                  Colors.grey,
                  () async {
                    await Clipboard.setData(ClipboardData(
                      text: '$content\n- ${data['author'] ?? 'User'} on TalkSpike',
                    ));
                    if (context.mounted) {
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

  Widget _action(IconData icon, String count, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            if (count.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(count, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
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
        'email': user.email ?? '',
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
  final GlobalKey<_HomeScreenState> _homeKey = GlobalKey<_HomeScreenState>();

  late final List<Widget> _screens = [
    HomeScreen(key: _homeKey),
    const ExploreScreen(),
    const NotificationsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: IndexedStack(index: _currentIndex, children: _screens),
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
              _buildNavItem(Icons.notifications_outlined, 2),
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
      onPressed: () => setState(() => _currentIndex = index),
    );
  }
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _postController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  String _selectedTag = '#tech';
  String _feedFilter = 'All';
  bool _isPosting = false;
  Uint8List? _pickedImage;
  Set<String> _following = <String>{};

  late final Stream<QuerySnapshot<Json>> _postsStream;
  StreamSubscription<DocumentSnapshot<Json>>? _meSub;

  @override
  void initState() {
    super.initState();
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();

    final me = FirebaseAuth.instance.currentUser;
    if (me != null) {
      _meSub = userDocStream(me.uid).listen(
        (snap) {
          if (!mounted) return;
          setState(() {
            _following = asStringList(snap.data()?['following']).toSet();
          });
        },
        onError: (_) {},
      );
    }
  }

  @override
  void dispose() {
    _meSub?.cancel();
    _postController.dispose();
    _composerFocus.dispose();
    super.dispose();
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
      final img = _pickedImage;
      if (img != null) {
        imageId = await TelegramStorage.uploadImage(img, caption: 'Post image | uid: ${user.uid}');
      }
      final prof = await PostService.myProfile();
      final String content = text.isEmpty ? _selectedTag : '$text $_selectedTag';
      await FirebaseFirestore.instance.collection('posts').add({
        'authorId': user.uid,
        'author': prof['name'],
        'handle': '@${user.email?.split('@')[0] ?? 'user'}',
        'authorPic': prof['photo'],
        'content': content,
        'tag': _selectedTag,
        if (imageId != null) 'imageId': imageId,
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
      }
      _showMessage('Thought published successfully!');
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  bool _matchesFilter(Json d) {
    switch (_feedFilter) {
      case '#Tech':
        return d['tag'] == '#tech';
      case 'Following':
        return _following.contains(d['authorId']) || _following.contains(d['reposterId']);
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: CustomScrollView(
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
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(color: kGreen)),
                  ),
                );
              }

              final docs = (snapshot.data?.docs ?? <QueryDocumentSnapshot<Json>>[])
                  .where((d) => _matchesFilter(d.data()))
                  .toList();

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
                  (context, index) => PostCard(key: ValueKey(docs[index].id), doc: docs[index]),
                  childCount: docs.length,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
                      onTap: () => setState(() => _feedFilter = filter),
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

  late final Stream<QuerySnapshot<Json>> _postsStream;
  late final Stream<QuerySnapshot<Json>> _usersStream;

  static const Map<String, String> _categories = {
    '#tech': 'Technology',
    '#AI': 'Artificial Intelligence',
    '#debate': 'Debate & Opinions',
  };

  @override
  void initState() {
    super.initState();
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots();
    _usersStream = FirebaseFirestore.instance.collection('users').limit(100).snapshots();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final String q = _query.trim().toLowerCase();

    return Scaffold(
      backgroundColor: kBg,
      appBar: buildTalkSpikeAppBar(currentUser),
      body: ListView(
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
          StreamBuilder<QuerySnapshot<Json>>(
            stream: _postsStream,
            builder: (context, postSnap) {
              if (postSnap.hasError) {
                return Text(
                  'Load nahi ho paaya: ${postSnap.error}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                );
              }
              if (!postSnap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: kGreen)),
                );
              }
              final posts = postSnap.data!.docs.where((d) => d.data()['repostOf'] == null).toList();
              return q.isEmpty ? _buildTrending(posts) : _buildSearchResults(posts, q);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrending(List<QueryDocumentSnapshot<Json>> posts) {
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
        StreamBuilder<QuerySnapshot<Json>>(
          stream: _usersStream,
          builder: (context, userSnap) {
            if (!userSnap.hasData) return const SizedBox.shrink();
            final myId = FirebaseAuth.instance.currentUser?.uid;
            final users = userSnap.data!.docs.where((u) => u.id != myId).take(5).toList();
            if (users.isEmpty) {
              return const Text('Abhi koi aur user nahi hai.',
                  style: TextStyle(color: Colors.grey));
            }
            return Column(children: users.map((u) => _buildUserTile(u.id, u.data())).toList());
          },
        ),
      ],
    );
  }

  Widget _buildSearchResults(List<QueryDocumentSnapshot<Json>> posts, String q) {
    final matched = posts.where((d) {
      final x = d.data();
      final hay =
          '${x['content'] ?? ''} ${x['author'] ?? ''} ${x['handle'] ?? ''} ${x['tag'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<QuerySnapshot<Json>>(
          stream: _usersStream,
          builder: (context, userSnap) {
            if (!userSnap.hasData) return const SizedBox.shrink();
            final people = userSnap.data!.docs.where((u) {
              final x = u.data();
              final hay = '${x['name'] ?? ''} ${x['email'] ?? ''}'.toLowerCase();
              return hay.contains(q);
            }).take(10).toList();
            if (people.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('People',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),
                ...people.map((u) => _buildUserTile(u.id, u.data())),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
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
    final String email = (u['email'] ?? '').toString();
    final String handle = email.contains('@') ? '@${email.split('@')[0]}' : '@user';
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
                  Text(handle,
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
      // orderBy nahi: where + orderBy ke liye composite index chahiye hota hai.
      // Sort neeche local hota hai.
      _stream = FirebaseFirestore.instance
          .collection('notifications')
          .where('receiverId', isEqualTo: user.uid)
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
                final docs = (snapshot.data?.docs ?? <QueryDocumentSnapshot<Json>>[]).toList()
                  ..sort((a, b) =>
                      millisOf(b.data()['timestamp']).compareTo(millisOf(a.data()['timestamp'])));

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
        final String email = (data['email'] ?? (_isOwn ? me?.email : '') ?? '').toString();
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
                IconButton(
                  tooltip: 'Logout',
                  icon: const Icon(Icons.logout, color: Colors.grey),
                  onPressed: () async {
                    // Agar ye profile push hua tha to pehle wapas aao.
                    final nav = Navigator.of(context);
                    if (nav.canPop()) nav.popUntil((r) => r.isFirst);
                    await signOutUser();
                  },
                ),
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
                                  email.contains('@') ? '@${email.split('@')[0]}' : '@user',
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
        final String id = await TelegramStorage.uploadImage(
          _newPhoto!,
          caption: 'Profile photo | uid: ${user.uid}',
        );
        update['photoUrl'] = 'tg:$id';
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
