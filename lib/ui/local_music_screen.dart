import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../api/definitions.dart';
import '../service/audio_service.dart';
import '../service/local_music.dart';

class LocalMusicScreen extends StatefulWidget {
  final LocalMusicLibrary? library;
  const LocalMusicScreen({super.key, this.library});
  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}
class _LocalMusicScreenState extends State<LocalMusicScreen> {
  late final LocalMusicLibrary _library = widget.library ?? LocalMusicLibrary.instance;
  List<LocalSong> _songs = [], _found = [];
  final Set<String> _selected = {};
  bool _busy = true, _preview = false;
  String? _message;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final songs = await _library.load(); if (mounted) setState(() => _songs = songs); }
    catch (_) { if (mounted) setState(() => _message = 'Impossibile leggere la libreria locale. Riprova.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _discover(bool folder) async {
    setState(() { _busy = true; _message = null; });
    try {
      final result = await _library.discover(folder: folder);
      if (!mounted || result['cancelled'] == true) return;
      final rows = (result['items'] as List).whereType<Map>().toList();
      final known = _songs.map((e) => e.uri).toSet(), identities = _songs.map((e) => e.identity).toSet();
      final candidates = rows.where(LocalSong.isMusic).map(LocalSong.fromMap).where((e) => !known.contains(e.uri) && !identities.contains(e.identity));
      final unique = <String, LocalSong>{};
      for (final song in candidates) { unique.putIfAbsent(song.identity, () => song); }
      setState(() {
        _found = unique.values.toList(); _selected..clear()..addAll(_found.map((e) => e.uri));
        _preview = _found.isNotEmpty;
        _message = '${_found.length} nuovi brani · ${rows.length - _found.length} esclusi o già presenti.'
          '${result['unreadable'] is num && result['unreadable'] > 0 ? ' Alcuni file non sono leggibili.' : ''}'
          '${result['truncated'] == true ? ' Scegli una sottocartella per completare la scansione.' : ''}';
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _message = e.code.contains('PERMISSION')
        ? 'Consenti l’accesso a musica e audio nelle impostazioni Android di VYBE MUSIC, poi riprova.'
        : 'Scansione non riuscita. Riprova o scegli una cartella accessibile.');
    } catch (_) { if (mounted) setState(() => _message = 'Scansione non riuscita. Riprova.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final count = await _library.importSongs(_found.where((e) => _selected.contains(e.uri)).toList());
      if (!mounted) return;
      setState(() { _preview = false; _message = '$count brani aggiunti. Pronti anche in modalità aereo.'; });
      await _load();
    } catch (_) { if (mounted) setState(() => _message = 'Importazione non completata. I file originali restano sul telefono. Riprova.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _play(int index) async {
    try {
      final tracks = _songs.map((e) => e.toTrack()).toList();
      await GetIt.I<AudioPlayerHandler>().playFromTrackList(tracks, tracks[index].id!,
        QueueSource(source: 'local', text: 'Musica sul dispositivo'), selectedIndex: index);
    } catch (_) { if (mounted) setState(() => _message = 'File non disponibile. Controlla che esista ancora e che VYBE MUSIC abbia accesso all’audio.'); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Musica sul dispositivo')),
    body: CustomScrollView(slivers: [
      SliverPadding(padding: const EdgeInsets.all(20), sliver: SliverToBoxAdapter(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('La tua musica è già qui.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Riconosciamo i file musicali e i loro tag. Vocali WhatsApp, registrazioni, suonerie e notifiche vengono esclusi. Nessun nuovo download.'),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _busy ? null : () => _discover(false), icon: const Icon(Icons.travel_explore_rounded), label: const Text('Scansiona telefono')),
            OutlinedButton.icon(onPressed: _busy ? null : () => _discover(true), icon: const Icon(Icons.folder_open_rounded), label: const Text('Scegli cartella')),
          ]),
          const SizedBox(height: 12),
          const ExpansionTile(tilePadding: EdgeInsets.zero, title: Text('Recuperare i download di ReFreezer'), children: [
            Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Mantieni installato il vecchio ReFreezer. Se i brani sono nella cartella Musica o Download, avvia la scansione. Se sono nella cartella privata della vecchia app, Android può bloccarne l’accesso: esportali dal vecchio ReFreezer o copiali in una cartella condivisa accessibile, poi usa “Scegli cartella”. I file senza estensione vengono verificati come audio. I download cifrati o incompleti non sono riproducibili.')),
          ]),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_message!)),
          if (_preview) ...[
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton(onPressed: _busy || _selected.isEmpty ? null : _import, child: Text('Importa ${_selected.length} brani')),
              TextButton(onPressed: _busy ? null : () => setState(() => _preview = false), child: const Text('Annulla')),
            ]),
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Seleziona tutti'), value: _selected.length == _found.length,
              onChanged: _busy ? null : (value) => setState(() { _selected.clear(); if (value == true) _selected.addAll(_found.map((e) => e.uri)); })),
          ] else Text('${_songs.length} brani nella libreria locale', style: Theme.of(context).textTheme.titleMedium),
        ]))),
      SliverList.builder(itemCount: _preview ? _found.length : _songs.length, itemBuilder: (context, index) {
        final song = (_preview ? _found : _songs)[index];
        final subtitle = '${song.artist.isEmpty ? 'Artista sconosciuto' : song.artist} · ${song.durationMs ~/ 60000}:${(song.durationMs ~/ 1000 % 60).toString().padLeft(2, '0')}';
        if (_preview) return CheckboxListTile(title: Text(song.title.isEmpty ? song.name : song.title), subtitle: Text(subtitle),
          value: _selected.contains(song.uri), onChanged: _busy ? null : (value) => setState(() { if (value == true) _selected.add(song.uri); else _selected.remove(song.uri); }));
        return ListTile(leading: const Icon(Icons.music_note_rounded), title: Text(song.title.isEmpty ? song.name : song.title), subtitle: Text(subtitle),
          onTap: _busy ? null : () => _play(index), trailing: IconButton(tooltip: 'Rimuovi dalla libreria, conserva il file', icon: const Icon(Icons.remove_circle_outline),
            onPressed: _busy ? null : () async {
              setState(() => _busy = true);
              try { await _library.remove(song.uri); await _load(); }
              catch (_) { if (mounted) setState(() { _busy = false; _message = 'Impossibile rimuovere il brano. Riprova.'; }); }
            }));
      }),
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]));
}
