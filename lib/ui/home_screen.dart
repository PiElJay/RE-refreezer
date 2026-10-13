import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../api/deezer.dart';
import '../api/definitions.dart';
import '../service/audio_service.dart';
import '../service/network_monitor.dart';
import '../settings.dart';
import '../translations.i18n.dart';
import '../ui/elements.dart';
import '../ui/menu.dart';
import 'details_screens.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';
import 'tiles.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: const HomeAppBar(),
        body: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SafeArea(child: Container()),
              const Flexible(
                child: HomePageScreen(),
              )
            ],
          ),
        ));
  }
}

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Size get preferredSize => AppBar().preferredSize;

  @override
  Widget build(BuildContext context) {
    return FreezerAppBar(
      'Home'.i18n,
      actions: <Widget>[
        IconButton(
          icon: Icon(
            Icons.file_download,
            semanticLabel: 'Download'.i18n,
          ),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const DownloadsScreen()));
          },
        ),
        IconButton(
          icon: Icon(
            Icons.settings,
            semanticLabel: 'Settings'.i18n,
          ),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const SettingsScreen()));
          },
        ),
      ],
    );
  }
}

class FreezerTitle extends StatelessWidget {
  const FreezerTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(children: [
        ClipRRect(borderRadius: BorderRadius.circular(24),
          child: Image.asset('assets/vybe_music.png', width: 200, height: 200, semanticLabel: 'VYBE MUSIC')),
        const SizedBox(height: 12),
        const Text('VYBE MUSIC', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
        const Text('PiElJay · Musica da Deezer', style: TextStyle(fontSize: 14)),
      ]),
    );
  }
}

class HomePageScreen extends StatefulWidget {
  final HomePage? homePage;
  final DeezerChannel? channel;
  final Future<HomePage> Function()? cacheLoader;
  final Future<HomePage> Function()? remoteLoader;
  final Future<void> Function(HomePage)? cacheWriter;
  const HomePageScreen({this.homePage, this.channel, this.cacheLoader,
    this.remoteLoader, this.cacheWriter, super.key});

  @override
  _HomePageScreenState createState() => _HomePageScreenState();
}

class _HomePageScreenState extends State<HomePageScreen> {
  HomePage? _homePage;
  int _loadGeneration = 0;
  bool _error = false;
  void _networkChanged() {
    if (mounted && !NetworkMonitor.instance.offline) {
      setState(() => _error = false);
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    bool active() => mounted && generation == _loadGeneration;
    void accept(HomePage page) {
      if (!active()) return;
      setState(() { _homePage = page; _error = false; });
    }
    if (widget.homePage != null && widget.homePage!.sections.isNotEmpty) {
      accept(widget.homePage!);
      return;
    }
    if (widget.channel == null && _homePage == null) {
      try {
        final page = await (widget.cacheLoader?.call() ?? HomePage().load());
        if (!active()) return;
        if (page.sections.isNotEmpty) accept(page);
      } catch (_) { /* Missing or old cache: still try the network. */ }
    }
    if (!active()) return;
    if (settings.offlineMode) {
      if (_homePage == null) setState(() => _error = true);
      return;
    }
    try {
      final page = await (widget.remoteLoader?.call() ??
        (widget.channel != null
          ? deezerAPI.getChannel(widget.channel?.target ?? '')
          : deezerAPI.homePage()));
      if (!active()) return;
      if (page.sections.isEmpty) throw StateError('Empty homepage');
      accept(page);
      if (widget.channel == null) {
        try {
          if (widget.cacheWriter != null) { await widget.cacheWriter!(page); }
          else { await page.save(); }
        } catch (_) { /* Cache failures must not hide fresh recommendations. */ }
      }
    } catch (_) {
      if (active() && _homePage == null) setState(() => _error = true);
    }
  }

  @override
  void initState() {
    super.initState();
    NetworkMonitor.instance.addListener(_networkChanged);
    _load();
  }

  @override
  void dispose() {
    ++_loadGeneration;
    NetworkMonitor.instance.removeListener(_networkChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error && _homePage == null)
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Suggerimenti Deezer momentaneamente non disponibili.'),
          TextButton(onPressed: () {
            setState(() => _error = false);
            _load();
          }, child: const Text('Riprova')),
        ]));
    if (_homePage == null) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(),
      ));
    }
    return Column(
        children: List.generate(
      _homePage?.sections.length ?? 0,
      (i) {
        switch (_homePage!.sections[i].layout) {
          case HomePageSectionLayout.ROW:
            return HomepageRowSection(_homePage!.sections[i]);
          case HomePageSectionLayout.GRID:
            return HomePageGridSection(_homePage!.sections[i]);
          default:
            return HomepageRowSection(_homePage!.sections[i]);
        }
      },
    ));
  }
}

class HomepageRowSection extends StatelessWidget {
  final HomePageSection section;
  const HomepageRowSection(this.section, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
          child: Text(
            section.title ?? '',
            textAlign: TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.w900),
          ),
        ),
        subtitle: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate((section.items?.length ?? 0) + 1, (j) {
              //Has more items
              if (j == (section.items?.length ?? 0)) {
                if (section.hasMore ?? false) {
                  return TextButton(
                    child: Text(
                      'Show more'.i18n,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20.0),
                    ),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: FreezerAppBar(section.title ?? ''),
                        body: SingleChildScrollView(
                            child: HomePageScreen(
                                channel:
                                    DeezerChannel(target: section.pagePath))),
                      ),
                    )),
                  );
                }
                return const SizedBox(height: 0, width: 0);
              }

              //Show item
              HomePageItem item = section.items![j] ?? HomePageItem();
              return HomePageItemWidget(item);
            }),
          ),
        ));
  }
}

class HomePageGridSection extends StatelessWidget {
  final HomePageSection section;
  const HomePageGridSection(this.section, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      title: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
        child: Text(
          section.title ?? '',
          textAlign: TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.w900),
        ),
      ),
      subtitle: Wrap(
        alignment: WrapAlignment.spaceAround,
        children: List.generate(section.items!.length, (i) {
          //Item
          return HomePageItemWidget(section.items![i] ?? HomePageItem());
        }),
      ),
    );
  }
}

class HomePageItemWidget extends StatelessWidget {
  final HomePageItem item;
  const HomePageItemWidget(this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    switch (item.type) {
      case HomePageItemType.FLOW:
        return FlowTrackListTile(
          item.value,
          onTap: () {
            DeezerFlow deezerFlow = item.value;
            GetIt.I<AudioPlayerHandler>().playFromSmartTrackList(SmartTrackList(
                id: 'flow', title: deezerFlow.title, flowType: deezerFlow.id));
          },
        );
      case HomePageItemType.SMARTTRACKLIST:
        return SmartTrackListTile(
          item.value,
          onTap: () {
            GetIt.I<AudioPlayerHandler>().playFromSmartTrackList(item.value);
          },
        );
      case HomePageItemType.ALBUM:
        return AlbumCard(
          item.value,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => AlbumDetails(item.value)));
          },
          onHold: () {
            MenuSheet m = MenuSheet();
            m.defaultAlbumMenu(item.value, context: context);
          },
        );
      case HomePageItemType.ARTIST:
        return ArtistTile(
          item.value,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ArtistDetails(item.value)));
          },
          onHold: () {
            MenuSheet m = MenuSheet();
            m.defaultArtistMenu(item.value, context: context);
          },
        );
      case HomePageItemType.PLAYLIST:
        return PlaylistCardTile(
          item.value,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => PlaylistDetails(item.value)));
          },
          onHold: () {
            MenuSheet m = MenuSheet();
            m.defaultPlaylistMenu(item.value, context: context);
          },
        );
      case HomePageItemType.CHANNEL:
        return ChannelTile(
          item.value,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => Scaffold(
                      appBar: FreezerAppBar(item.value.title.toString()),
                      body: SingleChildScrollView(
                          child: HomePageScreen(
                        channel: item.value,
                      )),
                    )));
          },
        );
      case HomePageItemType.SHOW:
        return ShowCard(
          item.value,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ShowScreen(item.value)));
          },
        );
      default:
        return const SizedBox(height: 0, width: 0);
    }
  }
}
