import Foundation
import KnowledgeWorkers

/// Fetch notes via JXA (osascript). Requires Automation permission for Notes.
public enum AppleNotesImport {
    public static func fetchNotes(limit: Int = 500) throws -> [SourceIngest.AppleNoteDTO] {
        let script = """
        (() => {
          const Notes = Application('Notes');
          const out = [];
          const notes = Notes.notes();
          const n = Math.min(notes.length, \(max(1, limit)));
          for (let i = 0; i < n; i++) {
            try {
              const note = notes[i];
              let folder = '';
              try {
                const c = note.container();
                if (c && c.name) folder = c.name();
              } catch (e) {}
              let body = '';
              try { body = note.plaintext(); } catch (e1) {
                try { body = note.body(); } catch (e2) { body = ''; }
              }
              // strip simple HTML if body() returned markup
              if (body && body.indexOf('<') >= 0) {
                body = body.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ');
              }
              out.push({
                id: String(note.id()),
                name: String(note.name()),
                body: String(body || ''),
                folder: String(folder || '')
              });
            } catch (e) {}
          }
          return JSON.stringify(out);
        })()
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-l", "JavaScript", "-e", script]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? "osascript failed"
            throw AppleNotesImportError.scriptFailed(msg)
        }
        guard !data.isEmpty else {
            throw AppleNotesImportError.scriptFailed("empty Notes payload")
        }
        return try JSONDecoder().decode([SourceIngest.AppleNoteDTO].self, from: data)
    }
}

public enum AppleNotesImportError: Error, LocalizedError {
    case scriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .scriptFailed(m):
            return "Apple Notes를 읽지 못했어요. 시스템 설정 → 개인정보 보호 → 자동화 에서 Knowledge → 메모 를 허용해 주세요. (\(m.prefix(120)))"
        }
    }
}
