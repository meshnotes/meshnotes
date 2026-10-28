import SwiftUI
import WidgetKit

struct RecentNote: Identifiable, Decodable {
  let id: String
  let title: String
  var url: URL {
    var components = URLComponents()
    components.scheme = "meshnotes"
    components.host = "widget"
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    components.percentEncodedPath = "/open/" + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    return components.url!
  }
}

struct NotesEntry: TimelineEntry {
  let date: Date
  let notes: [RecentNote]
}

struct NotesProvider: TimelineProvider {
  func placeholder(in context: Context) -> NotesEntry {
    NotesEntry(date: Date(), notes: [
      RecentNote(id: "preview-1", title: "Today's ideas"),
      RecentNote(id: "preview-2", title: "Next trip"),
      RecentNote(id: "preview-3", title: "Reading list"),
      RecentNote(id: "preview-4", title: "Weekend plans"),
      RecentNote(id: "preview-5", title: "Project notes"),
      RecentNote(id: "preview-6", title: "Little things")
    ])
  }

  func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
    completion(Timeline(entries: [load()], policy: .never))
  }

  private func load() -> NotesEntry {
    let raw = UserDefaults(suiteName: "group.xyz.meshnotes.meshnotes")?.string(forKey: "recent_notes") ?? "[]"
    let notes = (try? JSONDecoder().decode([RecentNote].self, from: Data(raw.utf8))) ?? []
    return NotesEntry(date: Date(), notes: Array(notes.prefix(6)))
  }
}

struct RecentNotesView: View {
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var colorScheme
  let entry: NotesEntry
  private var accent: Color { colorScheme == .dark ? Color(white: 0.80) : Color(white: 0.40) }
  private var surface: Color { colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.98) }

  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(surface, for: .widget)
    } else {
      content.padding(16).background(surface)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "note.text").foregroundColor(accent)
        Text("Recent notes").foregroundColor(.secondary)
        Spacer()
        Text("MeshNotes").font(.system(size: 10)).foregroundColor(.secondary)
      }
      .font(.system(size: 12, weight: .medium))
      .padding(.bottom, 4)
      if entry.notes.isEmpty {
        Text("No notes yet. Start writing.")
          .font(.system(size: 14)).foregroundColor(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      } else {
        ForEach(Array(entry.notes.prefix(family == .systemLarge ? 6 : 3))) { note in
          Link(destination: note.url) {
            HStack {
              Text(note.title).font(.system(size: 14)).lineLimit(1)
              Spacer(minLength: 0)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
        }
        if entry.notes.count < (family == .systemLarge ? 6 : 3) { Spacer(minLength: 0) }
      }
      Divider().padding(.vertical, 5)
      Link(destination: URL(string: "meshnotes://widget/new")!) {
        Label("New note", systemImage: "plus")
          .font(.system(size: 14, weight: .medium)).foregroundColor(accent)
          .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
          .contentShape(Rectangle())
      }
    }
  }
}

@main
struct RecentNotesWidget: Widget {
  let kind = "RecentNotesWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: NotesProvider()) { entry in
      RecentNotesView(entry: entry)
    }
    .configurationDisplayName("Recent notes")
    .description("Quickly open recent notes or create a new note.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}
