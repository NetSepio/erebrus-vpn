import 'legal_document_view.dart';

/// Erebrus privacy policy.
class PrivacyView extends LegalDocumentView {
  const PrivacyView({super.key})
      : super(
          title: 'Privacy Policy',
          sections: _sections,
        );

  static const _sections = [
    LegalSection(
      heading: 'Overview',
      body:
          'Erebrus VPN is built by NetSepio to give you sovereign control over how '
          'your traffic leaves your device. This policy explains what the client '
          'collects, what it does not collect, and what independent node operators '
          'may see.',
    ),
    LegalSection(
      heading: 'What we collect',
      body:
          'Account & entitlement\n'
          '• Wallet address or email used to authenticate with the NetSepio gateway.\n'
          '• Plan / trial status returned by the gateway.\n\n'
          'VPN provisioning\n'
          '• Your WireGuard public key (generated on-device) when registering a client.\n'
          '• Device label you assign during provisioning.\n\n'
          'Optional anonymous diagnostics (off by default)\n'
          '• Coarse health signals: app version, platform, VPN stage, region label.\n'
          '• No URLs, DNS queries, packet payloads, or browsing history.',
    ),
    LegalSection(
      heading: 'What we do not collect',
      body:
          '• Browsing history or in-app browser URLs.\n'
          '• DNS queries resolved through the tunnel.\n'
          '• Contents of VPN traffic.\n'
          '• Sale of connection metadata to advertisers.',
    ),
    LegalSection(
      heading: 'On-device data',
      body:
          'WireGuard private keys, session tokens, and cached credential bundles '
          'are stored in platform secure storage on your device. They are not '
          'uploaded to NetSepio except the public key required for provisioning.',
    ),
    LegalSection(
      heading: 'Exit nodes & gateways',
      body:
          'Community and premium nodes are operated by independent parties. As with '
          'any VPN, your exit node and gateway may observe egress IP addresses, '
          'connection timing, and bandwidth. Choose nodes you trust. NetSepio does '
          'not operate every node in the registry.',
    ),
    LegalSection(
      heading: 'Your choices',
      body:
          '• Disable anonymous diagnostics in Settings → Privacy.\n'
          '• Disconnect and delete the app to remove locally stored keys and tokens.\n'
          '• Contact NetSepio for data requests related to gateway-held account data.',
    ),
    LegalSection(
      heading: 'Updates',
      body:
          'We may update this policy as Erebrus matures. Material changes will be '
          'reflected in the app. Continued use after an update constitutes acceptance '
          'of the revised policy.\n\n'
          'Last updated: June 2026',
    ),
  ];
}