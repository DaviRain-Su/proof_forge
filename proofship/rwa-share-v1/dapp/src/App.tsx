import { useCallback, useEffect, useState, type FC } from "react";
import { Inspector } from "./Inspector";
import { RegistryPanel } from "./RegistryPanel";
import { StudioPanel } from "./StudioPanel";
import { loadLaunches, newLaunch, saveLaunches, type Launch } from "./studio/store";

export const App: FC = () => {
  const [view, setView] = useState<"studio" | "registry">("studio");
  const [launches, setLaunches] = useState<Launch[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);

  useEffect(() => {
    const loaded = loadLaunches();
    setLaunches(loaded);
    if (loaded[0]) setActiveId(loaded[0].id);
  }, []);

  const active = launches.find((l) => l.id === activeId) ?? null;

  const updateActive = useCallback(
    (next: Launch) => {
      setLaunches((prev) => {
        const rest = prev.filter((l) => l.id !== next.id);
        const merged = [next, ...rest];
        saveLaunches(merged);
        return merged;
      });
      setActiveId(next.id);
    },
    [],
  );

  const startNew = useCallback(() => {
    const l = newLaunch();
    setLaunches((prev) => {
      const merged = [l, ...prev];
      saveLaunches(merged);
      return merged;
    });
    setActiveId(l.id);
    setView("studio");
  }, []);

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <span className="gate-mark">⊢</span>
          <span className="brand-name">ProofShip</span>
        </div>

        <button type="button" className="new-launch" onClick={startNew}>
          + New launch
        </button>

        <nav className="launches" aria-label="launches">
          {launches.map((l) => (
            <button
              key={l.id}
              type="button"
              className={l.id === activeId ? "launch active" : "launch"}
              onClick={() => {
                setActiveId(l.id);
                setView("studio");
              }}
            >
              {l.title}
            </button>
          ))}
          {launches.length === 0 && <p className="muted side-note">No launches yet.</p>}
        </nav>

        <div className="side-foot">
          <button
            type="button"
            className={view === "studio" ? "side-link active" : "side-link"}
            onClick={() => setView("studio")}
          >
            Studio
          </button>
          <button
            type="button"
            className={view === "registry" ? "side-link active" : "side-link"}
            onClick={() => setView("registry")}
          >
            Registry
          </button>
          <span className="net-chip">x layer testnet · 1952 · OKB</span>
          <span className="powered">Powered by ProofForge · keys stay local</span>
        </div>
      </aside>

      <main className="main">
        {view === "studio" ? (
          active ? (
            <StudioPanel
              launch={active}
              onChange={updateActive}
              onOpenRegistry={() => setView("registry")}
            />
          ) : (
            <div className="chat">
              <div className="thread">
                <div className="empty-thread">
                  <p className="eyebrow">ProofShip Studio</p>
                  <h2>The gate decides what ships.</h2>
                  <p className="muted">
                    Start a new launch, describe the share rules, and watch the machine gate
                    decide. Certified proofs and the rejected negative live in the inspector.
                  </p>
                  <div className="actions">
                    <button type="button" onClick={startNew}>
                      + New launch
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )
        ) : (
          <div className="scroll-view">
            <RegistryPanel />
          </div>
        )}
      </main>

      {view === "studio" && (
        <Inspector launch={active} onOpenRegistry={() => setView("registry")} />
      )}
    </div>
  );
};
