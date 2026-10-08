import '../models/property_listing.dart';
import '../models/search_criteria.dart';

/// Common interface every portal-specific integration implements, so the UI
/// and local storage never need to know which portal a listing came from.
abstract class PortalAdapter {
  String get portalName;

  Future<List<PropertyListing>> search(SearchCriteria criteria, {int limit = 40});
}
