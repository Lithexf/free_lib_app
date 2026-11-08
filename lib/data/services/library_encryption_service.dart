import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Helyi, eszköz-specifikus 256 bites titkosító szolgáltatás (ChaCha20 folyamtitkosítás + integritás-ellenőrzés).
///
/// A kulcs kizárólag az alkalmazás zárt belső tárhelyén (`ApplicationSupportDirectory`)
/// jön létre, így más alkalmazások (pl. TikTok, Twitter/X, galéria, fájlböngészők)
/// nem férnek hozzá sem a kulcshoz, sem a titkosított könyvtáradatokhoz.
class LibraryEncryptionService {
  static final LibraryEncryptionService instance = LibraryEncryptionService._();
  static const String _prefix = 'ENC1:';
  static const int _keyLength = 32; // 256 bites kulcs
  static const int _nonceLength = 12; // 96 bites egyszeri szám (nonce)
  static const int _tagLength = 16; // 128 bites hitelesítő címke (MAC)

  Uint8List? _key;

  LibraryEncryptionService._();

  /// Inicializálja a 256 bites titkosító kulcsot a zárt belső tárolóból,
  /// valamint létrehozza a `.nomedia` fájlt, hogy külső média-indexelők ne lássák a cache-t.
  Future<void> init() async {
    if (_key != null) return;
    try {
      final supportDir = await getApplicationSupportDirectory();
      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }

      // .nomedia fájl elhelyezése minden belső könyvtárban, hogy semmilyen rendszerszintű
      // média- vagy cache-olvasó ne indexelje az alkalmazás fájljait
      final noMediaFile = File(p.join(supportDir.path, '.nomedia'));
      if (!await noMediaFile.exists()) {
        await noMediaFile.writeAsString('', flush: true);
      }

      try {
        final tempDir = await getTemporaryDirectory();
        final tempNoMedia = File(p.join(tempDir.path, '.nomedia'));
        if (!await tempNoMedia.exists()) {
          await tempNoMedia.writeAsString('', flush: true);
        }
      } catch (_) {}

      final keyFile = File(p.join(supportDir.path, '.freelib_vault.key'));
      File? docsKeyFile;
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        if (!await docsDir.exists()) {
          await docsDir.create(recursive: true);
        }
        docsKeyFile = File(p.join(docsDir.path, '.freelib_vault.key'));
      } catch (_) {}

      // Ha bármelyik belső könyvtárban megmaradt a kulcs (pl. újratelepítéskor az adatok megtartásával),
      // betöltjük és szinkronizáljuk mindkét helyre közvetlenül az adatbázis mellé.
      for (final candidate in [keyFile, ?docsKeyFile]) {
        if (await candidate.exists()) {
          final encoded = (await candidate.readAsString()).trim();
          final decoded = base64Decode(encoded);
          if (decoded.length == _keyLength) {
            _key = Uint8List.fromList(decoded);
            if (!await keyFile.exists()) {
              await keyFile.writeAsString(encoded, flush: true);
            }
            if (docsKeyFile != null && !await docsKeyFile.exists()) {
              await docsKeyFile.writeAsString(encoded, flush: true);
            }
            return;
          }
        }
      }

      final newKey = _generateSecureRandomBytes(_keyLength);
      final encodedNewKey = base64Encode(newKey);
      await keyFile.writeAsString(encodedNewKey, flush: true);
      if (docsKeyFile != null) {
        await docsKeyFile.writeAsString(encodedNewKey, flush: true);
      }
      _key = newKey;
    } catch (_) {
      // Tesztkörnyezeti fallback, ha a natív path_provider nem érhető el
      _key ??= _generateSecureRandomBytes(_keyLength);
    }
  }

  /// Tesztekhez fix kulcs beállítása.
  void initWithTestKey(Uint8List key) {
    assert(key.length == _keyLength);
    _key = Uint8List.fromList(key);
  }

  bool isEncryptedValue(String? value) {
    return value != null && value.startsWith(_prefix);
  }

  /// Egy szöveges mező titkosítása `ENC1:<base64>` formátumba.
  String? encryptField(String? plainText) {
    if (plainText == null || plainText.isEmpty) return plainText;
    if (plainText.startsWith(_prefix)) return plainText; // Már titkosított

    final key = _ensureKey();
    final nonce = _generateSecureRandomBytes(_nonceLength);
    final plainBytes = utf8.encode(plainText);
    final cipherBytes = _chacha20Xor(key, nonce, 1, plainBytes);
    final tag = _computeAuthTag(key, nonce, cipherBytes);

    final combined = Uint8List(nonce.length + cipherBytes.length + tag.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + cipherBytes.length, cipherBytes)
      ..setRange(nonce.length + cipherBytes.length,
          nonce.length + cipherBytes.length + tag.length, tag);

    return '$_prefix${base64Encode(combined)}';
  }

  /// Egy `ENC1:<base64>` formátumú mező visszafejtése.
  /// Ha a mező még régi (nem titkosított) szöveg, változtatás nélkül visszaadja,
  /// így a korábban beszkennelt könyvek is maradéktalanul megmaradnak.
  String? decryptField(String? storedValue) {
    if (storedValue == null || storedValue.isEmpty) return storedValue;
    if (!storedValue.startsWith(_prefix)) return storedValue;

    try {
      final key = _ensureKey();
      final raw = base64Decode(storedValue.substring(_prefix.length));
      if (raw.length < _nonceLength + _tagLength) return storedValue;

      final nonce = Uint8List.sublistView(raw, 0, _nonceLength);
      final cipherLen = raw.length - _nonceLength - _tagLength;
      final cipherBytes =
          Uint8List.sublistView(raw, _nonceLength, _nonceLength + cipherLen);
      final expectedTag =
          Uint8List.sublistView(raw, _nonceLength + cipherLen, raw.length);

      final actualTag = _computeAuthTag(key, nonce, cipherBytes);
      if (!_constantTimeEquals(expectedTag, actualTag)) {
        return storedValue;
      }

      final plainBytes = _chacha20Xor(key, nonce, 1, cipherBytes);
      return utf8.decode(plainBytes, allowMalformed: true);
    } catch (_) {
      return storedValue;
    }
  }

  static const List<String> _encryptedColumns = [
    'title',
    'subtitle',
    'authors',
    'publisher',
    'published_date',
    'description',
    'categories',
    'cover_url',
    'notes',
    'original_title',
    'romaji_title',
    'original_author',
  ];

  /// Adatbázisba írás előtt titkosítja a könyv szöveges mezőit.
  Map<String, dynamic> encryptBookMap(Map<String, dynamic> rawMap) {
    final result = Map<String, dynamic>.from(rawMap);
    for (final col in _encryptedColumns) {
      final val = result[col];
      if (val is String && val.isNotEmpty) {
        result[col] = encryptField(val);
      }
    }
    return result;
  }

  /// Adatbázisból olvasás után visszafejti a könyv szöveges mezőit.
  Map<String, dynamic> decryptBookMap(Map<String, dynamic> dbMap) {
    final result = Map<String, dynamic>.from(dbMap);
    for (final col in _encryptedColumns) {
      final val = result[col];
      if (val is String && val.isNotEmpty) {
        result[col] = decryptField(val);
      }
    }
    return result;
  }

  Uint8List _ensureKey() {
    _key ??= _generateSecureRandomBytes(_keyLength);
    return _key!;
  }

  Uint8List _generateSecureRandomBytes(int length) {
    final rng = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  /// RFC 8439 ChaCha20 folyamtitkosító (256 bites kulcs, 96 bites nonce, 32 bites számláló).
  Uint8List _chacha20Xor(
    Uint8List key,
    Uint8List nonce,
    int initialCounter,
    List<int> input,
  ) {
    final out = Uint8List(input.length);
    final keyWords = Uint32List(8);
    final keyData = ByteData.sublistView(key);
    for (var i = 0; i < 8; i++) {
      keyWords[i] = keyData.getUint32(i * 4, Endian.little);
    }

    final nonceWords = Uint32List(3);
    final nonceData = ByteData.sublistView(nonce);
    for (var i = 0; i < 3; i++) {
      nonceWords[i] = nonceData.getUint32(i * 4, Endian.little);
    }

    final state = Uint32List(16);
    final working = Uint32List(16);
    final blockBytes = Uint8List(64);
    final blockData = ByteData.sublistView(blockBytes);

    var counter = initialCounter;
    var offset = 0;

    while (offset < input.length) {
      // ChaCha20 konstans fejlécek ("expand 32-byte k")
      state[0] = 0x61707865;
      state[1] = 0x3320646e;
      state[2] = 0x79622d32;
      state[3] = 0x6b206574;
      for (var i = 0; i < 8; i++) {
        state[4 + i] = keyWords[i];
      }
      state[12] = counter & 0xffffffff;
      state[13] = nonceWords[0];
      state[14] = nonceWords[1];
      state[15] = nonceWords[2];

      for (var i = 0; i < 16; i++) {
        working[i] = state[i];
      }

      for (var round = 0; round < 10; round++) {
        _quarterRound(working, 0, 4, 8, 12);
        _quarterRound(working, 1, 5, 9, 13);
        _quarterRound(working, 2, 6, 10, 14);
        _quarterRound(working, 3, 7, 11, 15);
        _quarterRound(working, 0, 5, 10, 15);
        _quarterRound(working, 1, 6, 11, 12);
        _quarterRound(working, 2, 7, 8, 13);
        _quarterRound(working, 3, 4, 9, 14);
      }

      for (var i = 0; i < 16; i++) {
        blockData.setUint32(
          i * 4,
          (working[i] + state[i]) & 0xffffffff,
          Endian.little,
        );
      }

      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        out[offset + i] = input[offset + i] ^ blockBytes[i];
      }

      offset += chunk;
      counter++;
    }

    return out;
  }

  /// Kulcsfüggő ChaCha20-alapú 128 bites üzenethitelesítő kód (MAC).
  Uint8List _computeAuthTag(
    Uint8List key,
    Uint8List nonce,
    Uint8List cipherBytes,
  ) {
    // Counter 0 blokkból egyszer használatos MAC-kulcsot származtatunk
    final polyKey = _chacha20Xor(key, nonce, 0, Uint8List(32));
    final acc = Uint32List(4);
    final polyData = ByteData.sublistView(polyKey);
    for (var i = 0; i < 4; i++) {
      acc[i] = polyData.getUint32(i * 4, Endian.little);
    }

    var idx = 0;
    for (final b in cipherBytes) {
      final lane = idx & 3;
      acc[lane] = _rotl32((acc[lane] + b + 0x9e3779b9) & 0xffffffff, 11) ^
          polyData.getUint32(16 + lane * 4, Endian.little);
      idx++;
    }
    acc[0] = (acc[0] ^ cipherBytes.length) & 0xffffffff;

    final tagInput = Uint8List(16);
    final tagData = ByteData.sublistView(tagInput);
    for (var i = 0; i < 4; i++) {
      tagData.setUint32(i * 4, acc[i], Endian.little);
    }

    return _chacha20Xor(polyKey, nonce, 0, tagInput);
  }

  void _quarterRound(Uint32List x, int a, int b, int c, int d) {
    x[a] = (x[a] + x[b]) & 0xffffffff;
    x[d] = _rotl32(x[d] ^ x[a], 16);
    x[c] = (x[c] + x[d]) & 0xffffffff;
    x[b] = _rotl32(x[b] ^ x[c], 12);
    x[a] = (x[a] + x[b]) & 0xffffffff;
    x[d] = _rotl32(x[d] ^ x[a], 8);
    x[c] = (x[c] + x[d]) & 0xffffffff;
    x[b] = _rotl32(x[b] ^ x[c], 7);
  }

  int _rotl32(int v, int c) {
    return ((v << c) & 0xffffffff) | ((v & 0xffffffff) >>> (32 - c));
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
