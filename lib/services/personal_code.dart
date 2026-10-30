import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'vault_service.dart';

/// The personal code of an employee: three simple words and a number,
/// like `river-tiger-mango-42`. Made by the app, easy to remember.
///
/// It is the only key to the account:
/// - Login: a hidden Firebase login is made from it (see [loginEmail]).
///   The code itself is never saved in Firebase.
/// - History: the locked list of "my posts" opens with it.
///
/// About 500 words x 3 + a number from 10 to 99: about 11 billion
/// codes. Guessing online is blocked by Firebase (too many tries), and the
/// hidden login is made with a slow hash, so trying codes one by one is
/// very slow too.
class PersonalCode {
  PersonalCode._();

  static final Random _random = Random.secure();

  /// A new random code, like "river-tiger-mango-42".
  static String generate() {
    String pick() => words[_random.nextInt(words.length)];
    var a = pick(), b = pick(), c = pick();
    while (b == a) {
      b = pick();
    }
    while (c == a || c == b) {
      c = pick();
    }
    final n = 10 + _random.nextInt(90);
    return '$a-$b-$c-$n';
  }

  /// "River Tiger, mango42 " -> "river-tiger-mango-42".
  static String normalize(String code) {
    final s = code
        .toLowerCase()
        // "mango42" -> "mango 42"
        .replaceAllMapped(RegExp(r'([a-z])([0-9])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([0-9])([a-z])'), (m) => '${m[1]} ${m[2]}');
    final parts = s.split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty);
    return parts.join('-');
  }

  /// True if it looks like a personal code: 3 known words and a number.
  static bool looksValid(String code) {
    final p = normalize(code).split('-');
    return p.length == 4 &&
        _set.contains(p[0]) &&
        _set.contains(p[1]) &&
        _set.contains(p[2]) &&
        RegExp(r'^[0-9]{2}$').hasMatch(p[3]);
  }

  /// The hidden Firebase login for a code: a slow hash of the code, as
  /// 64 letters, plus "@code.haystekpulse.app". No mail is ever sent to it.
  /// Runs in the background, so the screen does not freeze.
  static Future<String> loginEmail(String code, String domain) async {
    final bytes = await compute(_slowHash, normalize(code));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$hex@$domain';
  }

  /// The Firebase password for a code (the code itself).
  static String password(String code) => normalize(code);

  static final Set<String> _set = words.toSet();

  static const List<String> words = [
  'apple', 'mango', 'grape', 'lemon', 'peach', 'melon', 'berry', 'cherry',
  'banana', 'guava', 'papaya', 'orange', 'plum', 'kiwi', 'lime', 'coconut',
  'almond', 'cashew', 'walnut', 'peanut', 'tiger', 'lion', 'zebra', 'horse',
  'camel', 'goat', 'sheep', 'cow', 'deer', 'rabbit', 'panda', 'koala',
  'monkey', 'parrot', 'eagle', 'falcon', 'pigeon', 'sparrow', 'crow', 'swan',
  'duck', 'goose', 'owl', 'peacock', 'robin', 'otter', 'beaver', 'turtle',
  'dolphin', 'whale', 'shark', 'salmon', 'tuna', 'crab', 'lobster',
  'octopus', 'squid', 'snail', 'frog', 'toad', 'lizard', 'snake', 'cobra',
  'python', 'fox', 'wolf', 'bear', 'moose', 'bison', 'yak', 'llama',
  'alpaca', 'puppy', 'kitten', 'mouse', 'hamster', 'squirrel', 'hedgehog',
  'badger', 'mole', 'bee', 'wasp', 'ant', 'moth', 'spider', 'beetle',
  'cricket', 'lark', 'finch', 'heron', 'stork', 'crane', 'pelican',
  'penguin', 'seal', 'walrus', 'rhino', 'hippo', 'giraffe', 'cheetah',
  'leopard', 'jaguar', 'puma', 'lynx', 'hyena', 'gazelle', 'donkey', 'mule',
  'pony', 'bull', 'calf', 'lamb', 'chick', 'hen', 'rooster', 'turkey',
  'quail', 'dove', 'raven', 'magpie', 'river', 'ocean', 'lake', 'pond',
  'stream', 'brook', 'creek', 'bay', 'beach', 'coast', 'island', 'valley',
  'canyon', 'hill', 'mountain', 'peak', 'cliff', 'cave', 'desert', 'forest',
  'jungle', 'meadow', 'field', 'garden', 'park', 'orchard', 'farm',
  'prairie', 'glacier', 'volcano', 'harbor', 'shore', 'lagoon', 'delta',
  'marsh', 'swamp', 'spring', 'well', 'fountain', 'sun', 'moon', 'star',
  'comet', 'planet', 'galaxy', 'cloud', 'rain', 'snow', 'storm', 'thunder',
  'breeze', 'wind', 'frost', 'dew', 'mist', 'fog', 'rainbow', 'sky', 'dawn',
  'dusk', 'sunset', 'sunrise', 'noon', 'night', 'winter', 'summer', 'autumn',
  'season', 'ember', 'flame', 'spark', 'blaze', 'candle', 'lamp', 'lantern',
  'torch', 'beacon', 'red', 'blue', 'green', 'yellow', 'purple', 'pink',
  'brown', 'black', 'white', 'silver', 'golden', 'violet', 'indigo', 'amber',
  'coral', 'ivory', 'olive', 'maroon', 'navy', 'teal', 'crimson', 'scarlet',
  'azure', 'cyan', 'magenta', 'beige', 'cream', 'copper', 'bronze',
  'emerald', 'ruby', 'pearl', 'jade', 'topaz', 'opal', 'quartz', 'marble',
  'granite', 'table', 'chair', 'sofa', 'bench', 'desk', 'shelf', 'drawer',
  'window', 'door', 'gate', 'fence', 'bridge', 'tower', 'castle', 'palace',
  'temple', 'cottage', 'cabin', 'tent', 'igloo', 'pencil', 'eraser',
  'crayon', 'marker', 'brush', 'canvas', 'paper', 'book', 'letter', 'stamp',
  'ticket', 'wallet', 'basket', 'bucket', 'bottle', 'cup', 'mug', 'bowl',
  'plate', 'spoon', 'fork', 'knife', 'kettle', 'teapot', 'oven', 'stove',
  'clock', 'watch', 'mirror', 'pillow', 'blanket', 'carpet', 'curtain',
  'ladder', 'hammer', 'wrench', 'drill', 'shovel', 'rake', 'anchor',
  'compass', 'map', 'globe', 'rocket', 'plane', 'train', 'truck', 'bus',
  'taxi', 'bicycle', 'scooter', 'boat', 'ship', 'yacht', 'canoe', 'kayak',
  'sail', 'wheel', 'engine', 'guitar', 'piano', 'violin', 'flute', 'drum',
  'trumpet', 'harp', 'banjo', 'cello', 'bell', 'whistle', 'radio', 'camera',
  'phone', 'laptop', 'robot', 'magnet', 'battery', 'button', 'bread',
  'butter', 'cheese', 'honey', 'sugar', 'salt', 'pepper', 'ginger', 'garlic',
  'onion', 'potato', 'tomato', 'carrot', 'pumpkin', 'cabbage', 'spinach',
  'pea', 'bean', 'corn', 'rice', 'noodle', 'pasta', 'pizza', 'burger',
  'sandwich', 'cookie', 'muffin', 'cake', 'candy', 'toffee', 'jelly',
  'yogurt', 'coffee', 'cocoa', 'juice', 'soup', 'salad', 'pickle', 'tulip',
  'rose', 'lily', 'lotus', 'daisy', 'jasmine', 'orchid', 'sunflower',
  'poppy', 'iris', 'maple', 'oak', 'pine', 'cedar', 'willow', 'bamboo',
  'palm', 'fern', 'cactus', 'moss', 'ivy', 'clover', 'leaf', 'petal', 'seed',
  'root', 'branch', 'acorn', 'cone', 'pebble', 'stone', 'rock', 'sand',
  'clay', 'crystal', 'diamond', 'gem', 'shell', 'feather', 'happy', 'brave',
  'calm', 'kind', 'bold', 'quick', 'swift', 'bright', 'clever', 'gentle',
  'jolly', 'lucky', 'merry', 'proud', 'quiet', 'shiny', 'sunny', 'warm',
  'cozy', 'fresh', 'kite', 'yoyo', 'puzzle', 'balloon', 'ribbon', 'badge',
  'medal', 'trophy', 'crown', 'helmet', 'jacket', 'scarf', 'mitten', 'glove',
  'boot', 'sandal', 'hat', 'cap', 'circle', 'square', 'triangle', 'arrow',
  'heart', 'spiral', 'wave', 'zigzag', 'dot', 'cube', 'sphere', 'prism',
  'ring', 'loop', 'knot', 'thread', 'needle', 'hero', 'pilot', 'sailor',
  'farmer', 'baker', 'chef', 'doctor', 'nurse', 'artist', 'dancer', 'singer',
  'poet', 'writer', 'painter', 'builder', 'ranger', 'scout', 'wizard',
  'knight', 'dragon', 'unicorn', 'phoenix', 'griffin', 'giant', 'elf',
  'pixie', 'fairy', 'genie', 'goblin', 'troll', 'mermaid', 'captain',
  'pirate', 'explorer', 'astronaut',
  ];
}

/// Top level, so it can run in a background isolate.
Uint8List _slowHash(String code) =>
    VaultService.pbkdf2(code, base64Encode(utf8.encode('haystek-pulse-login-v1')), 100000);
