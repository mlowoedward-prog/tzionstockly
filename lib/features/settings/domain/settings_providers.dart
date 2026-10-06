import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localeProvider = StateProvider<Locale>((ref) => const Locale('en'));

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final negativeStockBehaviorProvider = StateProvider<String>((ref) => 'warn'); // 'warn' or 'block'

final slowMoverDaysProvider = StateProvider<int>((ref) => 30);

final appLockEnabledProvider = StateProvider<bool>((ref) => false);
