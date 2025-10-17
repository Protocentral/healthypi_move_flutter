/// Represents a GitHub firmware release for HealthyPi Move
class FirmwareRelease {
  final String version;
  final String tagName;
  final String name;
  final String body;          // Release notes (markdown)
  final DateTime publishedAt;
  final String downloadUrl;
  final int? fileSize;

  FirmwareRelease({
    required this.version,
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.downloadUrl,
    this.fileSize,
  });

  /// Create from GitHub API JSON response
  factory FirmwareRelease.fromGitHubJson(Map<String, dynamic> json) {
    // Extract version from tag (remove 'v' prefix if present)
    final tagName = json['tag_name'] as String;
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    // Find the firmware ZIP asset
    final assets = json['assets'] as List<dynamic>;
    Map<String, dynamic>? firmwareAsset;

    try {
      firmwareAsset = assets.firstWhere(
        (asset) => (asset['name'] as String).toLowerCase().contains('healthypi_move_update'),
        orElse: () => null,
      ) as Map<String, dynamic>?;
    } catch (e) {
      firmwareAsset = null;
    }

    return FirmwareRelease(
      version: version,
      tagName: tagName,
      name: json['name'] as String? ?? 'Release $version',
      body: json['body'] as String? ?? '',
      publishedAt: DateTime.parse(json['published_at'] as String),
      downloadUrl: firmwareAsset?['browser_download_url'] as String? ?? '',
      fileSize: firmwareAsset?['size'] as int?,
    );
  }

  /// Get formatted release date
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(publishedAt);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${publishedAt.year}-${publishedAt.month.toString().padLeft(2, '0')}-${publishedAt.day.toString().padLeft(2, '0')}';
    }
  }

  /// Get formatted file size
  String get formattedFileSize {
    if (fileSize == null) return 'Unknown size';

    final sizeInMB = fileSize! / (1024 * 1024);
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(2)} MB';
    } else {
      final sizeInKB = fileSize! / 1024;
      return '${sizeInKB.toStringAsFixed(0)} KB';
    }
  }

  @override
  String toString() => 'FirmwareRelease(version: $version, published: $formattedDate)';
}
