import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/gateway_auth_client.dart';
import '../../auth/wallet_auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../vpn/gateway_controller.dart';
import '../../vpn/vpn_models.dart';

Future<void> showOrganizationsSheet(
  BuildContext context,
  WalletAuthController auth,
) async {
  if (!auth.isAuthenticated) {
    Get.snackbar('Sign in required', 'Connect your account first',
        snackPosition: SnackPosition.BOTTOM);
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _OrganizationsSheet(auth: auth),
  );
}

class _OrganizationsSheet extends StatefulWidget {
  const _OrganizationsSheet({required this.auth});

  final WalletAuthController auth;

  @override
  State<_OrganizationsSheet> createState() => _OrganizationsSheetState();
}

class _OrganizationsSheetState extends State<_OrganizationsSheet> {
  @override
  void initState() {
    super.initState();
    widget.auth.refreshAccountOrgInvites();
  }

  void _create() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => _CreateOrgSheet(auth: widget.auth),
    );
  }

  Future<void> _accept(String orgId) async {
    try {
      await widget.auth.acceptAccountOrgInvite(orgId);
      Get.snackbar('Joined', 'Organization joined', snackPosition: SnackPosition.BOTTOM);
    } on AuthException catch (e) {
      Get.snackbar('Invite', e.message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _decline(String orgId) async {
    try {
      await widget.auth.declineAccountOrgInvite(orgId);
      Get.snackbar('Invite', 'Invitation declined', snackPosition: SnackPosition.BOTTOM);
    } on AuthException catch (e) {
      Get.snackbar('Invite', e.message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gateway = Get.isRegistered<GatewayController>()
        ? Get.find<GatewayController>()
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          22, 18, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('Organizations',
                        style: grotesk(
                            size: 18, weight: FontWeight.w600))),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close,
                      size: 20, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Workspaces you belong to and pending invitations.',
              style: grotesk(
                  size: 13, color: AppColors.textTertiary, height: 1.4),
            ),
            const SizedBox(height: 16),
            Obx(() {
              final orgs = gateway?.orgs ?? [];
              if (orgs.isEmpty && widget.auth.accountOrgInvites.isEmpty) {
                return _Empty(
                  message:
                      'You are not in any organizations yet. Create one to get started.',
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (orgs.isNotEmpty) ...[
                    _SectionTitle('Your organizations'),
                    ...orgs.map((o) => _OrgRow(org: o)),
                  ],
                  if (widget.auth.accountOrgInvites.isNotEmpty) ...[
                    if (orgs.isNotEmpty) const SizedBox(height: 18),
                    _SectionTitle('Pending invites'),
                    ...widget.auth.accountOrgInvites.map((i) => _InviteRow(
                          invite: i,
                          onAccept: () => _accept(i.orgId),
                          onDecline: () => _decline(i.orgId),
                        )),
                  ],
                ],
              );
            }),
            const SizedBox(height: 18),
            Obx(() {
              if (widget.auth.isLoadingAccountOrgInvites.value) {
                return const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent)));
              }
              return GestureDetector(
                onTap: _create,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'CREATE ORGANIZATION',
                    style: mono(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppColors.onAccent),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: mono(
            size: 11,
            weight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 1.2),
      ),
    );
  }
}

class _OrgRow extends StatelessWidget {
  const _OrgRow({required this.org});
  final VpnOrg org;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  org.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: grotesk(size: 14.5, weight: FontWeight.w600),
                ),
                if (org.role != null && org.role!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${org.role!.toUpperCase()}${org.plan != null && org.plan!.isNotEmpty ? ' · ${org.plan!.toUpperCase()}' : ''}',
                    style: mono(
                        size: 11,
                        weight: FontWeight.w500,
                        color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final UserOrgInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invite.orgName,
            style: grotesk(size: 14.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Invited as ${invite.role ?? 'member'}',
            style: mono(
                size: 11,
                weight: FontWeight.w500,
                color: AppColors.textTertiary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'ACCEPT',
                      style: mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: AppColors.onAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onDecline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.strokeSoft),
                    ),
                    child: Text(
                      'DECLINE',
                      style: mono(
                          size: 12,
                          weight: FontWeight.w600,
                          color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: grotesk(
            size: 13, weight: FontWeight.w400, color: AppColors.textMuted),
      ),
    );
  }
}

class _CreateOrgSheet extends StatefulWidget {
  const _CreateOrgSheet({required this.auth});

  final WalletAuthController auth;

  @override
  State<_CreateOrgSheet> createState() => _CreateOrgSheetState();
}

class _CreateOrgSheetState extends State<_CreateOrgSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _slugCtrl;
  var _creating = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _slugCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  String _slugFromName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final slug = _slugCtrl.text.trim().toLowerCase();
    if (name.isEmpty) {
      Get.snackbar('Create organization', 'Enter an organization name',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (slug.isEmpty) {
      Get.snackbar('Create organization', 'Enter an organization slug',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() => _creating = true);
    try {
      await widget.auth.createOrg(name: name, slug: slug);
      if (mounted) Navigator.of(context).pop();
      Get.snackbar('Organization created', name,
          snackPosition: SnackPosition.BOTTOM);
    } on AuthException catch (e) {
      Get.snackbar('Create organization', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          22, 18, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create organization',
                style: grotesk(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Create a workspace to manage private nodes and team access.',
              style: grotesk(
                  size: 13, color: AppColors.textTertiary, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) {
                if (_slugCtrl.text.isEmpty) {
                  _slugCtrl.text = _slugFromName(v);
                }
              },
              decoration: const InputDecoration(hintText: 'Organization name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _slugCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'organization-slug',
                helperText: 'Lowercase letters, numbers and hyphens only',
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _creating ? null : _create,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _creating ? 'CREATING…' : 'CREATE ORGANIZATION',
                  style: mono(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.onAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
