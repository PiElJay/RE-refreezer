import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../api/cache.dart';
import '../api/definitions.dart';
import '../service/audio_service.dart';
import '../service/network_monitor.dart';
import 'cached_image.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'library.dart';
import 'local_music_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class MusicDashboard extends StatefulWidget {
  const MusicDashboard({super.key});
  @override
  State<MusicDashboard> createState() => _MusicDashboardState();
}

class _MusicDashboardState extends State<MusicDashboard> {
  int _revision = 0;
  Future<void> _refresh() async {
    await NetworkMonitor.instance.refresh();
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final handler = GetIt.I<AudioPlayerHandler>();
    final recent = cache.history.reversed.take(8).toList();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Padding(padding: const EdgeInsets.only(right: 12), child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/vybe_music.png', width: 54, height: 54, semanticLabel: 'VYBE MUSIC'))),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VYBE MUSIC · DEEZER',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2,
                                color: Color(0xff61d8ff),
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Trova il tuo ritmo.',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Impostazioni',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 24), sliver: SliverToBoxAdapter(child: Card(
                child: ListTile(leading: const Icon(Icons.library_music_rounded, color: Color(0xff61d8ff)),
                  title: const Text('La musica che hai già'), subtitle: const Text('Importa i brani dal telefono'), trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocalMusicScreen())))))),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: NetworkMonitor.instance,
                    builder: (context, online, _) => Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            avatar: Icon(
                              online
                                  ? Icons.wifi_rounded
                                  : Icons.offline_pin_rounded,
                              size: 16,
                            ),
                            label: Text(
                              online
                                  ? 'Connesso a Deezer'
                                  : 'Offline · brani scaricati',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xff75144e),
                                Color(0xff152d52),
                                Color(0xff191922),
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.graphic_eq_rounded,
                                size: 42,
                                color: Color(0xffd9c3ff),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                online
                                    ? 'Il tuo Flow.\nLa tua atmosfera.'
                                    : 'Nessuna rete.\nTutta la tua musica.',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  height: 1.1,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                online
                                    ? 'Un mix Deezer che segue i tuoi gusti.'
                                    : 'Ascolta i brani disponibili sul telefono.',
                                style: const TextStyle(
                                  color: Color(0xffd1c6e4),
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: () async {
                                  if (online) {
                                    await handler.playFromSmartTrackList(
                                      SmartTrackList(id: 'flow'),
                                    );
                                  } else if (context.mounted) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const DownloadsScreen(),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(
                                  online
                                      ? Icons.play_arrow_rounded
                                      : Icons.offline_pin_rounded,
                                ),
                                label: Text(
                                  online ? 'Avvia Flow' : 'Apri Download',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: StreamBuilder<MediaItem?>(
                    stream: handler.mediaItem,
                    builder: (context, snapshot) {
                      final item = snapshot.data;
                      if (item == null) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedImage(
                              url: item.artUri?.toString() ?? '',
                              width: 56,
                              height: 56,
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.open_in_full_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PlayerScreen(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _shortcut(
                          context,
                          constraints.maxWidth,
                          'Download',
                          'Sempre con te',
                          Icons.offline_pin_rounded,
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DownloadsScreen(),
                            ),
                          ),
                        ),
                        _shortcut(
                          context,
                          constraints.maxWidth,
                          'La tua libreria',
                          'Brani, album e playlist',
                          Icons.library_music_rounded,
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LibraryScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (recent.isNotEmpty) ...[
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Riascolta',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 196,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        final track = recent[index];
                        return SizedBox(
                          width: 140,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => handler.playFromTrackList(
                              recent,
                              track.id!,
                              QueueSource(source: 'history', text: 'Riascolta'),
                              selectedIndex: index,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: CachedImage(
                                    url: track.albumArt?.thumb ?? '',
                                    width: 140,
                                    height: 140,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  track.title ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  track.artistString ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 28, 24, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Scopri su Deezer',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: HomePageScreen(key: ValueKey(_revision)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcut(
    BuildContext context,
    double width,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback tap,
  ) {
    final cardWidth = width < 340 ? width : (width - 12) / 2;
    return SizedBox(
      width: cardWidth,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
