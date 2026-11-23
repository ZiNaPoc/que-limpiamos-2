import 'package:flutter/foundation.dart';
import 'api_client.dart';
class Session extends ChangeNotifier {
  Session._();

  static final Session instance = Session._();

  ApiUser? _user;

  ApiUser? get user => _user;
  bool get isLoggedIn => _user != null;

  void start(ApiUser user) {
    _user = user;
    notifyListeners();
  }

  void clear() {
    _user = null;
    notifyListeners();
  }
}