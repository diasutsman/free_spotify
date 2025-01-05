// Playlist Detail Screen
import 'package:flutter/material.dart';
import 'package:free_spotify/main.dart';
import 'package:get/get.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;

  const PlaylistDetailScreen({
    required this.playlistId,
    required this.playlistName,
    super.key,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final PlaylistController playlistController = Get.find<PlaylistController>();

  @override
  void initState() {
    playlistController.loadPlaylistTracks(widget.playlistId);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName),
        backgroundColor: Colors.black,
      ),
      body: Obx(
        () => playlistController.isLoading.value
            ? Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount:
                    playlistController.selectedPlaylist.value?.tracks.length ??
                        0,
                itemBuilder: (context, index) {
                  final track =
                      playlistController.selectedPlaylist.value!.tracks[index];
                  return ListTile(
                    leading: track.albumArt.isNotEmpty
                        ? Image.network(
                            track.albumArt,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Icon(Icons.music_note, size: 48),
                    title: Text(track.name),
                    subtitle: Text(track.artist),
                    trailing: Text(
                      '${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(color: Colors.grey),
                    ),
                    onTap: () => Get.find<PlayerController>().setTrack(track),
                  );
                },
              ),
      ),
    );
  }
}
