import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";

import "package:inventree/app_colors.dart";
import "package:inventree/user_profile.dart";
import "package:inventree/l10.dart";
import "package:inventree/api.dart";
import "package:inventree/settings/sso_login.dart";
import "package:inventree/widget/dialogs.dart";
import "package:inventree/widget/progress.dart";

class InvenTreeLoginWidget extends StatefulWidget {
  const InvenTreeLoginWidget(this.profile) : super();

  final UserProfile profile;

  @override
  _InvenTreeLoginState createState() => _InvenTreeLoginState();
}

class _InvenTreeLoginState extends State<InvenTreeLoginWidget> {
  final formKey = GlobalKey<FormState>();

  String username = "";
  String password = "";

  bool _obscured = true;

  String error = "";

  // Attempt login via Username and Password
  Future<void> _doLogin(BuildContext context) async {
    // Save form
    formKey.currentState?.save();

    bool valid = formKey.currentState?.validate() ?? false;

    if (valid) {
      // Dismiss the keyboard
      FocusScopeNode currentFocus = FocusScope.of(context);

      if (!currentFocus.hasPrimaryFocus) {
        currentFocus.unfocus();
      }

      showLoadingOverlay();

      // Attempt login - suppress the generic error dialog, since this screen
      // shows its own contextual inline error message below
      final response = await InvenTreeAPI().fetchToken(
        widget.profile,
        username,
        password,
        showDialog: false,
      );

      if (response.successful()) {
        // A token was issued - immediately connect using it, then return
        // directly to the home screen (rather than leaving the user on the
        // server-selector screen to navigate back manually)
        await InvenTreeAPI().connectToServer(widget.profile);

        hideLoadingOverlay();

        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        hideLoadingOverlay();
        var data = response.asMap();

        String err;

        if (data.containsKey("detail")) {
          err = (data["detail"] ?? "") as String;
        } else {
          err = statusCodeToString(response.statusCode);
        }
        setState(() {
          error = err;
        });
      }
    }
  }

  // Open In-App SSO / OIDC (Authentik) Login
  Future<void> _openSSOLogin(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => InvenTreeSSOLoginWidget(widget.profile),
      ),
    );

    if (result == true && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // Manually enter an existing API token
  Future<void> _enterTokenManually(BuildContext context) async {
    String manualToken = "";
    final tokenFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(L10().enterTokenManually),
          content: Form(
            key: tokenFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10().tokenPrompt,
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "inv-...",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(TablerIcons.key),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return L10().valueCannotBeEmpty;
                    }
                    return null;
                  },
                  onSaved: (value) {
                    manualToken = value?.trim() ?? "";
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10().cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                if (tokenFormKey.currentState?.validate() ?? false) {
                  tokenFormKey.currentState?.save();
                  Navigator.of(ctx).pop();

                  showLoadingOverlay();
                  final bool valid = await InvenTreeAPI().testToken(
                    widget.profile,
                    manualToken,
                  );

                  if (valid) {
                    widget.profile.token = manualToken;
                    await UserProfileDBManager().updateProfile(widget.profile);
                    await InvenTreeAPI().connectToServer(widget.profile);
                    hideLoadingOverlay();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  } else {
                    hideLoadingOverlay();
                    if (mounted) {
                      setState(() {
                        error = L10().tokenInvalid;
                      });
                    }
                  }
                }
              },
              child: Text(L10().profileConnect),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> before = [
      ListTile(
        title: Text(L10().loginEnter),
        subtitle: Text(L10().loginEnterDetails),
        leading: Icon(TablerIcons.user_check),
      ),
      ListTile(
        title: Text(L10().server),
        subtitle: Text(widget.profile.server),
        leading: Icon(TablerIcons.server),
      ),
      Divider(),
    ];

    List<Widget> after = [];

    if (error.isNotEmpty) {
      after.add(Divider());
      after.add(
        ListTile(
          leading: Icon(TablerIcons.exclamation_circle, color: COLOR_DANGER),
          title: Text(L10().error, style: TextStyle(color: COLOR_DANGER)),
          subtitle: Text(error, style: TextStyle(color: COLOR_DANGER)),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(L10().login),
        actions: [
          IconButton(
            icon: Icon(TablerIcons.transition_right, color: COLOR_SUCCESS),
            onPressed: () async {
              _doLogin(context);
            },
          ),
        ],
      ),
      body: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...before,
              // SSO / OIDC (Authentik) Login Card
              Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(TablerIcons.shield_lock),
                        label: Text(
                          L10().ssoLogin,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _openSSOLogin(context),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        L10().ssoLoginDetails,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      L10().or.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: InputDecoration(
                  labelText: L10().username,
                  labelStyle: TextStyle(fontWeight: FontWeight.bold),
                  hintText: L10().enterUsername,
                ),
                initialValue: "",
                keyboardType: TextInputType.text,
                onSaved: (value) {
                  username = value?.trim() ?? "";
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return L10().usernameEmpty;
                  }

                  return null;
                },
              ),
              TextFormField(
                decoration: InputDecoration(
                  labelText: L10().password,
                  labelStyle: TextStyle(fontWeight: FontWeight.bold),
                  hintText: L10().enterPassword,
                  suffixIcon: IconButton(
                    icon: _obscured
                        ? Icon(TablerIcons.eye)
                        : Icon(TablerIcons.eye_off),
                    onPressed: () {
                      setState(() {
                        _obscured = !_obscured;
                      });
                    },
                  ),
                ),
                initialValue: "",
                keyboardType: TextInputType.visiblePassword,
                obscureText: _obscured,
                onSaved: (value) {
                  password = value?.trim() ?? "";
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return L10().passwordEmpty;
                  }

                  return null;
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  icon: const Icon(TablerIcons.key, size: 18),
                  label: Text(L10().enterTokenManually),
                  onPressed: () => _enterTokenManually(context),
                ),
              ),
              ...after,
            ],
          ),
          padding: EdgeInsets.all(16),
        ),
      ),
    );
  }
}
