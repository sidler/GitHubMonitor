import Foundation

/// Moving an item to another column of a board.
///
/// Like a label and unlike an approval: nobody is notified, nothing is
/// published, and the way back is the same menu again -- so this is the
/// second write in the app with no question in front of it.
public enum ProjectQuery {
    /// Reading boards needs `read:project`; moving something on one needs
    /// the whole `project` scope, which GitHub has no read-write split
    /// for. A token without it is refused by name, so the menu is only
    /// offered where the scope is there.
    public static let scope = "project"

    public static let document = """
    mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $project, itemId: $item, fieldId: $field,
        value: { singleSelectOptionId: $option }
      }) {
        projectV2Item { id }
      }
    }
    """
}
