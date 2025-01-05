import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:free_spotify/app_interceptor.dart';
import 'package:free_spotify/env.dart';
import 'package:free_spotify/pkce_helper.dart';
import 'package:get/get.dart' hide FormData;
import 'package:dio/dio.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

// API Service
class SpotifyApiService {
  static final SpotifyApiService _instance = SpotifyApiService._internal();
  factory SpotifyApiService() => _instance;
  SpotifyApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.spotify.com/v1',
    validateStatus: (status) => status! < 500,
  ))
    ..interceptors.addAll([
      AppInterceptor(),
    ]);

  final Dio _authDio = Dio(BaseOptions(
    baseUrl: 'https://accounts.spotify.com/api',
    validateStatus: (status) => status! < 500,
  ))
    ..interceptors.addAll([
      AppInterceptor(),
    ]);

  void setAccessToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<String?> getAccessToken(String code) async {
    try {
      final response = await _authDio.post(
        '/token',
        data: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': REDIRECT_URI,
        },
        options: Options(
          headers: {
            'content-type': 'application/x-www-form-urlencoded',
            'Authorization':
                'Basic ${base64Encode(utf8.encode('$CLIENT_ID:$CLIENT_SECRET'))}',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data['access_token'];
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to get access token',
      );
    } catch (e) {
      print('Error getting access token: $e');
      return null;
    }
  }

  Future<List<Playlist>> getUserPlaylists() async {
    try {
      final response = await _dio.get('/me/playlists');

      if (response.statusCode == 200) {
        return (response.data['items'] as List)
            .map((item) => Playlist(
                  id: item['id'],
                  name: item['name'],
                  imageUrl: item['images']?[0]?['url'] ?? '',
                  tracks: [],
                ))
            .toList();
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch playlists',
      );
    } catch (e) {
      print('Error fetching playlists: $e');
      return [];
    }
  }

  Future<List<Track>> getPlaylistTracks(String playlistId) async {
    try {
      final response = await _dio.get('/playlists/$playlistId/tracks');

      if (response.statusCode == 200) {
        return (response.data['items'] as List).map((item) {
          final track = item['track'];
          return Track(
            id: track['id'],
            name: track['name'],
            artist: track['artists'][0]['name'],
            albumArt: track['album']['images'][0]['url'],
            duration: Duration(milliseconds: track['duration_ms']),
          );
        }).toList();
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch tracks',
      );
    } catch (e) {
      print('Error fetching tracks: $e');
      return [];
    }
  }
}

// Constants
String CLIENT_ID = Env.clientId;
String CLIENT_SECRET = Env.clientSecret;
const String REDIRECT_URI = 'free-spotify://callback';

// Models
class Track {
  final String id;
  final String name;
  final String artist;
  final String albumArt;
  final Duration duration;

  Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.albumArt,
    required this.duration,
  });
}

class Playlist {
  final String id;
  final String name;
  final String imageUrl;
  final List<Track> tracks;

  Playlist({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.tracks,
  });
}

// Auth Controller
class AuthController extends GetxController {
  final _apiService = SpotifyApiService();
  var accessToken = ''.obs;
  var isLoggedIn = false.obs;
  var isLoading = false.obs;

  @override
  void onInit() {
    initUniLinks();
    super.onInit();
  }

  Future<void> initUniLinks() async {
    try {
      AppLinks().uriLinkStream.listen((Uri uri) async {
        log('Deep link received: ${uri.toString()}');

        if (uri.toString().contains('code=')) {
          final code = uri.queryParameters['code'];
          if (code != null) {
            await handleAuthCode(code);
          }
        }
      });
    } catch (e) {
      print('Error initializing deep links: $e');
    }
  }

  Future<void> handleAuthCode(String code) async {
    isLoading.value = true;
    try {
      final token = await _apiService.getAccessToken(code);
      if (token != null) {
        accessToken.value = token;
        _apiService.setAccessToken(token);
        isLoggedIn.value = true;
        Get.find<PlaylistController>().fetchPlaylists();
      } else {
        Get.snackbar('Error', 'Failed to retrieve access token');
      }
    } catch (e) {
      print('Error handling auth code: $e');
      Get.snackbar('Error', 'Authentication failed: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login() async {
    isLoading.value = true;
    try {
      final url = Uri.parse(
        'https://accounts.spotify.com/authorize'
        '?client_id=$CLIENT_ID'
        '&response_type=code'
        '&redirect_uri=${Uri.encodeComponent(REDIRECT_URI)}'
        '&scope=playlist-read-private%20user-library-read',
      );

      if (!await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not launch Spotify authentication');
      }
    } catch (e) {
      print('Login error: $e');
      Get.snackbar('Error', 'Login failed: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void logout() {
    accessToken.value = '';
    isLoggedIn.value = false;
    Get.find<PlaylistController>().playlists.clear();
  }
}

// Playlist Controller
class PlaylistController extends GetxController {
  final _apiService = SpotifyApiService();
  var playlists = <Playlist>[].obs;
  var isLoading = false.obs;
  var selectedPlaylist = Rx<Playlist?>(null);

  Future<void> fetchPlaylists() async {
    isLoading.value = true;
    try {
      final fetchedPlaylists = await _apiService.getUserPlaylists();
      playlists.value = fetchedPlaylists;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadPlaylistTracks(String playlistId) async {
    isLoading.value = true;
    try {
      final tracks = await _apiService.getPlaylistTracks(playlistId);
      final playlistIndex = playlists.indexWhere((p) => p.id == playlistId);
      if (playlistIndex != -1) {
        final updatedPlaylist = Playlist(
          id: playlists[playlistIndex].id,
          name: playlists[playlistIndex].name,
          imageUrl: playlists[playlistIndex].imageUrl,
          tracks: tracks,
        );
        playlists[playlistIndex] = updatedPlaylist;
        selectedPlaylist.value = updatedPlaylist;
      }
    } finally {
      isLoading.value = false;
    }
  }
}

// Player Controller
class PlayerController extends GetxController {
  var currentTrack = Rx<Track?>(null);
  var isPlaying = false.obs;
  var currentPosition = Duration.zero.obs;

  void togglePlay() {
    isPlaying.value = !isPlaying.value;
  }

  void setTrack(Track track) {
    currentTrack.value = track;
    isPlaying.value = true;
  }
}

// Login Screen
class LoginScreen extends StatelessWidget {
  final authController = Get.find<AuthController>();

  LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Obx(() => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.network(
                  'https://storage.googleapis.com/pr-newsroom-wp/1/2018/11/Spotify_Logo_RGB_White.png',
                  width: 200,
                ),
                SizedBox(height: 50),
                if (authController.isLoading.value)
                  CircularProgressIndicator(color: Colors.green[700])
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding:
                          EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                    ),
                    onPressed: () => authController.login(),
                    child: Text('Login with Spotify'),
                  ),
              ],
            )),
      ),
    );
  }
}

// Home Screen
class HomeScreen extends StatelessWidget {
  final PlaylistController playlistController = Get.find<PlaylistController>();

  HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text('Your Playlists'),
                actions: [
                  IconButton(
                    icon: Icon(Icons.logout),
                    onPressed: () => Get.find<AuthController>().logout(),
                  ),
                ],
              ),
              Expanded(
                child: Obx(
                  () => playlistController.isLoading.value
                      ? Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: playlistController.playlists.length,
                          itemBuilder: (context, index) {
                            final playlist =
                                playlistController.playlists[index];
                            return ListTile(
                              leading: playlist.imageUrl.isNotEmpty
                                  ? Image.network(
                                      playlist.imageUrl,
                                      width: 48,
                                      height: 48,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildPlaceholder(),
                                    )
                                  : _buildPlaceholder(),
                              title: Text(playlist.name),
                              onTap: () => playlistController
                                  .loadPlaylistTracks(playlist.id),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NowPlayingBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      color: Colors.grey[800],
      child: Icon(Icons.music_note),
    );
  }
}

// Now Playing Bar
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(
      builder: (controller) {
        if (controller.currentTrack.value == null) return SizedBox.shrink();

        return Container(
          height: 64,
          color: Colors.grey[900],
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                margin: EdgeInsets.all(8),
                color: Colors.grey[800],
                child: Icon(Icons.music_note),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.currentTrack.value!.name,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      controller.currentTrack.value!.artist,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  controller.isPlaying.value ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: controller.togglePlay,
              ),
            ],
          ),
        );
      },
    );
  }
}

// App
class SpotifyCloneApp extends StatelessWidget {
  const SpotifyCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Spotify Clone',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green[700],
        scaffoldBackgroundColor: Colors.black,
      ),
      home: AuthWrapper(),
    );
  }
}

// Auth Wrapper
class AuthWrapper extends StatelessWidget {
  final AuthController authController = Get.put(AuthController());
  final PlaylistController playlistController = Get.put(PlaylistController());
  final PlayerController playerController = Get.put(PlayerController());

  AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
        () => authController.isLoggedIn.value ? HomeScreen() : LoginScreen());
  }
}

void main() {
  runApp(SpotifyCloneApp());
}
