/// GNS Search Bar Widget
/// 
/// Search field for @handles and public keys.
/// 
/// Location: lib/ui/widgets/gns_search_bar.dart

import 'package:flutter/material.dart';

class GnsSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSearch;

  const GnsSearchBar({super.key, required this.controller, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Search @handle or public key...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => onSearch(controller.text),
        ),
      ),
      onSubmitted: onSearch,
    );
  }
}
