import 'legal_document_view.dart';

/// Erebrus terms of use.
class TermsView extends LegalDocumentView {
  const TermsView({super.key})
      : super(
          title: 'Terms of Use',
          sections: _sections,
        );

  static const _sections = [
    LegalSection(
      heading: 'Agreement',
      body:
          'By installing or using Erebrus VPN you agree to these Terms of Use and '
          'the Privacy Policy. If you do not agree, do not use the service.',
    ),
    LegalSection(
      heading: 'The service',
      body:
          'Erebrus is a client application that connects you to NetSepio gateways '
          'and community-operated VPN nodes over WireGuard or Stealth transports. '
          'Features, node availability, and protocols may change as the network evolves.',
    ),
    LegalSection(
      heading: 'Acceptable use',
      body:
          'You agree to:\n\n'
          '• Comply with applicable laws in your jurisdiction.\n'
          '• Not use Erebrus for abuse, fraud, spam, or attacks on third parties.\n'
          '• Not attempt to disrupt gateways, nodes, or other users.\n'
          '• Respect the policies of node operators you connect through.',
    ),
    LegalSection(
      heading: 'Community nodes',
      body:
          'Nodes listed in the app may be run by independent operators. NetSepio '
          'does not guarantee their uptime, logging practices, or geographic claims. '
          'Premium or curated nodes may be subject to separate operator agreements.',
    ),
    LegalSection(
      heading: 'Beta software',
      body:
          'Erebrus is under active development. Features may be added, changed, or '
          'removed without notice. You use pre-release builds at your own risk.',
    ),
    LegalSection(
      heading: 'Disclaimer',
      body:
          'THE SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. NETSEPIO '
          'DISCLAIMS LIABILITY FOR INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES '
          'TO THE MAXIMUM EXTENT PERMITTED BY LAW. VPN connectivity does not guarantee '
          'anonymity against all adversaries.',
    ),
    LegalSection(
      heading: 'Termination',
      body:
          'We may suspend gateway access for violations of these terms. You may stop '
          'using the service at any time by disconnecting and uninstalling the app.',
    ),
    LegalSection(
      heading: 'Contact',
      body:
          'Enterprise terms, node operator agreements, and legal inquiries: contact '
          'NetSepio through official channels.\n\n'
          'Last updated: June 2026',
    ),
  ];
}