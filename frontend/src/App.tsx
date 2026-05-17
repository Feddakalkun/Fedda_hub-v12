import { useEffect, useMemo, useState } from "react";

type SectionId = "home" | "image" | "video" | "tools" | "settings" | "chat";
type ImageSubView = "menu" | "chroma" | "downloads";
type DownloadState = "idle" | "queued" | "installing" | "done" | "error";

type SystemStatsResponse = {
  system?: {
    ram_total?: number;
    ram_free?: number;
  };
  devices?: Array<{
    name?: string;
    type?: string;
    vram_total?: number;
    vram_free?: number;
  }>;
};

type QueueStatus = {
  total_count: number;
  done_count: number;
  in_progress_count: number;
  is_processing: boolean;
};

type StatusState = {
  connected: boolean;
  ramText: string;
  vramText: string;
};

type ManifestModel = {
  name?: string;
  type?: string;
  base: string;
  save_path: string;
  description?: string;
  reference?: string;
  filename: string;
  url?: string;
};

type ManagerModel = ManifestModel & {
  installed?: string | boolean;
  ui_id?: string;
  size?: string;
};

type ChromaManifest = {
  id: string;
  name: string;
  cardImage: string;
  workflowFile: string;
  requiredModels: ManifestModel[];
};

const COMFY_STATS_URL = "/api/comfy/system_stats";
const COMFY_MODEL_LIST_URL = "/api/comfy/externalmodel/getlist?mode=default";
const COMFY_INSTALL_MODEL_URL = "/api/comfy/manager/queue/install_model";
const COMFY_QUEUE_START_URL = "/api/comfy/manager/queue/start";
const COMFY_QUEUE_STATUS_URL = "/api/comfy/manager/queue/status";
const CHROMA_MANIFEST_URL = "/workflows/chroma/manifest.json";
const HF_STORAGE_KEY = "fedda_hf_key";

function toGb(value?: number) {
  if (!value || Number.isNaN(value)) return 0;
  return value / (1024 * 1024 * 1024);
}

function formatUsage(used: number, total: number) {
  if (!total || total <= 0) return "n/a";
  return `${used.toFixed(1)} / ${total.toFixed(1)} GB`;
}

function keyForModel(model: { filename: string; save_path: string; base: string }) {
  return `${model.filename}@@${model.save_path}@@${model.base}`;
}

function isInstalled(value: string | boolean | undefined) {
  if (typeof value === "boolean") return value;
  return (value || "").toLowerCase() === "true";
}

export default function App() {
  const [showHfModal, setShowHfModal] = useState(false);
  const [hfKey, setHfKey] = useState("");
  const [section, setSection] = useState<SectionId>("home");
  const [imageSubView, setImageSubView] = useState<ImageSubView>("menu");
  const [status, setStatus] = useState<StatusState>({
    connected: false,
    ramText: "n/a",
    vramText: "n/a"
  });
  const [queueStatus, setQueueStatus] = useState<QueueStatus>({
    total_count: 0,
    done_count: 0,
    in_progress_count: 0,
    is_processing: false
  });
  const [chromaManifest, setChromaManifest] = useState<ChromaManifest | null>(null);
  const [modelIndex, setModelIndex] = useState<Record<string, ManagerModel>>({});
  const [downloadState, setDownloadState] = useState<Record<string, DownloadState>>({});
  const [downloadError, setDownloadError] = useState<string>("");

  useEffect(() => {
    const saved = window.localStorage.getItem(HF_STORAGE_KEY) || "";
    if (!saved) {
      setShowHfModal(true);
      return;
    }
    setHfKey(saved);
  }, []);

  useEffect(() => {
    let cancelled = false;

    const loadStats = async () => {
      try {
        const res = await fetch(COMFY_STATS_URL, { method: "GET" });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = (await res.json()) as SystemStatsResponse;

        const ramTotal = toGb(data.system?.ram_total);
        const ramFree = toGb(data.system?.ram_free);
        const ramUsed = Math.max(0, ramTotal - ramFree);

        const cudaDevice = (data.devices || []).find((d) => (d.type || "").toLowerCase() === "cuda");
        const vramTotal = toGb(cudaDevice?.vram_total);
        const vramFree = toGb(cudaDevice?.vram_free);
        const vramUsed = Math.max(0, vramTotal - vramFree);

        if (!cancelled) {
          setStatus({
            connected: true,
            ramText: formatUsage(ramUsed, ramTotal),
            vramText: formatUsage(vramUsed, vramTotal)
          });
        }
      } catch {
        if (!cancelled) {
          setStatus({
            connected: false,
            ramText: "n/a",
            vramText: "n/a"
          });
        }
      }
    };

    void loadStats();
    const interval = setInterval(() => void loadStats(), 5000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const loadManifest = async () => {
      try {
        const res = await fetch(CHROMA_MANIFEST_URL, { method: "GET" });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const manifest = (await res.json()) as ChromaManifest;
        if (!cancelled) setChromaManifest(manifest);
      } catch {
        if (!cancelled) setChromaManifest(null);
      }
    };
    void loadManifest();
    return () => {
      cancelled = true;
    };
  }, []);

  const refreshModelList = async () => {
    const res = await fetch(COMFY_MODEL_LIST_URL, { method: "GET" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = (await res.json()) as { models?: ManagerModel[] };
    const index: Record<string, ManagerModel> = {};
    for (const model of data.models || []) {
      if (!model.filename || !model.save_path || !model.base) continue;
      index[keyForModel(model as { filename: string; save_path: string; base: string })] = model;
    }
    setModelIndex(index);
  };

  const refreshQueueStatus = async () => {
    const res = await fetch(COMFY_QUEUE_STATUS_URL, { method: "GET" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const queue = (await res.json()) as QueueStatus;
    setQueueStatus(queue);
    return queue;
  };

  useEffect(() => {
    let cancelled = false;

    const initialLoad = async () => {
      try {
        await Promise.all([refreshModelList(), refreshQueueStatus()]);
      } catch {
        if (!cancelled) {
          setQueueStatus({ total_count: 0, done_count: 0, in_progress_count: 0, is_processing: false });
        }
      }
    };

    void initialLoad();
    const interval = setInterval(async () => {
      try {
        const queue = await refreshQueueStatus();
        if (!queue.is_processing) {
          await refreshModelList();
        }
      } catch {
        if (!cancelled) {
          setQueueStatus({ total_count: 0, done_count: 0, in_progress_count: 0, is_processing: false });
        }
      }
    }, 3000);

    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  useEffect(() => {
    if (queueStatus.is_processing) {
      setDownloadState((prev) => {
        const next = { ...prev };
        for (const key of Object.keys(next)) {
          if (next[key] === "queued") next[key] = "installing";
        }
        return next;
      });
      return;
    }

    setDownloadState((prev) => {
      const next = { ...prev };
      for (const key of Object.keys(next)) {
        if (next[key] === "installing" || next[key] === "queued") next[key] = "done";
      }
      return next;
    });
  }, [queueStatus.is_processing]);

  const statusClass = useMemo(
    () => (status.connected ? "status-chip is-online" : "status-chip is-offline"),
    [status.connected]
  );

  const modelRows = useMemo(() => {
    if (!chromaManifest?.requiredModels) return [];
    return chromaManifest.requiredModels.map((m) => {
      const key = keyForModel(m);
      const managerEntry = modelIndex[key];
      const installed = managerEntry ? isInstalled(managerEntry.installed) : false;
      const state = downloadState[key] || "idle";
      return {
        ...m,
        key,
        managerEntry,
        installed,
        state
      };
    });
  }, [chromaManifest, modelIndex, downloadState]);

  const saveHfKey = () => {
    const trimmed = hfKey.trim();
    if (!trimmed) return;
    window.localStorage.setItem(HF_STORAGE_KEY, trimmed);
    setHfKey(trimmed);
    setShowHfModal(false);
  };

  const queueInstallModel = async (row: (typeof modelRows)[number]) => {
    setDownloadError("");
    const payload: ManagerModel = {
      ...(row.managerEntry || {}),
      name: row.managerEntry?.name || row.filename,
      type: row.managerEntry?.type || "custom",
      base: row.base,
      save_path: row.save_path,
      filename: row.filename,
      url: row.managerEntry?.url || row.url,
      description: row.managerEntry?.description || row.description,
      reference: row.managerEntry?.reference || row.reference,
      ui_id: row.key
    };

    if (!payload.url) {
      setDownloadError(`No download URL found for ${row.filename}`);
      setDownloadState((prev) => ({ ...prev, [row.key]: "error" }));
      return;
    }

    try {
      setDownloadState((prev) => ({ ...prev, [row.key]: "queued" }));
      const installRes = await fetch(COMFY_INSTALL_MODEL_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      if (!installRes.ok) {
        const msg = await installRes.text();
        throw new Error(msg || `install_model failed (${installRes.status})`);
      }

      const startRes = await fetch(COMFY_QUEUE_START_URL, { method: "POST" });
      if (!startRes.ok && startRes.status !== 201) {
        const msg = await startRes.text();
        throw new Error(msg || `queue/start failed (${startRes.status})`);
      }

      await refreshQueueStatus();
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setDownloadError(message);
      setDownloadState((prev) => ({ ...prev, [row.key]: "error" }));
    }
  };

  const mainCards: Array<{ id: SectionId; title: string; bg: string }> = [
    { id: "image", title: "IMAGE", bg: "/card-images/image.png" },
    { id: "video", title: "VIDEO", bg: "/card-images/video.png" },
    { id: "tools", title: "TOOLS", bg: "/card-images/tools.png" },
    { id: "settings", title: "SETTINGS", bg: "/card-images/settings.png" },
    { id: "chat", title: "CHAT", bg: "/card-images/chat.png" }
  ];

  const onMainCardClick = (id: SectionId) => {
    setSection(id);
    if (id === "image") {
      setImageSubView("menu");
    }
  };

  const renderSection = () => {
    if (section === "home") {
      return (
        <section className="cards-only">
          {mainCards.map((card) => (
            <button
              key={card.id}
              className="feature-card has-image"
              style={{ backgroundImage: `url(${card.bg})` }}
              aria-label={card.title}
              title={card.title}
              onClick={() => onMainCardClick(card.id)}
            />
          ))}
        </section>
      );
    }

    if (section !== "image") {
      return (
        <section className="panel">
          <h2>{section.toUpperCase()}</h2>
          <p>Standard base is ready. Workflows will be added here next.</p>
          <button className="panel-btn" onClick={() => setSection("home")}>
            Back to front cards
          </button>
        </section>
      );
    }

    if (imageSubView === "menu") {
      return (
        <section className="panel">
          <div className="panel-head">
            <h2>IMAGE</h2>
            <button className="panel-btn" onClick={() => setSection("home")}>
              Back
            </button>
          </div>
          <div className="image-subcards">
            <button
              className="feature-card subcard has-image"
              style={{ backgroundImage: "url(/card-images/chroma.png)" }}
              aria-label="CHROMA"
              title="CHROMA"
              onClick={() => setImageSubView("chroma")}
            />
            <button className="downloads-card" onClick={() => setImageSubView("downloads")}>
              <span>DOWNLOADS</span>
              <small>Model installer for workflows</small>
            </button>
          </div>
        </section>
      );
    }

    return (
      <section className="panel">
        <div className="panel-head">
          <h2>{imageSubView === "chroma" ? "CHROMA WORKFLOW" : "MODEL DOWNLOADS"}</h2>
          <div className="panel-head-actions">
            <button className="panel-btn" onClick={() => setImageSubView("menu")}>
              Back to IMAGE
            </button>
            <button className="panel-btn" onClick={() => setSection("home")}>
              Front cards
            </button>
          </div>
        </div>

        {imageSubView === "chroma" && (
          <div className="chroma-summary">
            <p>{chromaManifest?.name || "Chroma workflow"}</p>
            <a className="panel-btn link-btn" href={chromaManifest?.workflowFile || "#"} target="_blank" rel="noreferrer">
              Open workflow JSON
            </a>
            <button className="panel-btn" onClick={() => setImageSubView("downloads")}>
              Open Downloads
            </button>
          </div>
        )}

        <div className="queue-line">
          <span>Queue: {queueStatus.in_progress_count} running</span>
          <span>{queueStatus.done_count}/{queueStatus.total_count} done</span>
          <span>{queueStatus.is_processing ? "Processing" : "Idle"}</span>
        </div>
        {downloadError && <div className="error-line">{downloadError}</div>}

        <div className="model-table">
          {modelRows.map((row) => (
            <div key={row.key} className="model-row">
              <div className="model-info">
                <strong>{row.filename}</strong>
                <span>{row.save_path}</span>
              </div>
              <div className="model-state">
                {row.installed ? "Installed" : row.state === "idle" ? "Missing" : row.state}
              </div>
              <button
                className="panel-btn"
                disabled={row.installed || row.state === "queued" || row.state === "installing"}
                onClick={() => void queueInstallModel(row)}
              >
                {row.installed ? "Installed" : row.state === "queued" || row.state === "installing" ? "Queued" : "Download"}
              </button>
            </div>
          ))}
        </div>
      </section>
    );
  };

  return (
    <main className="home">
      {showHfModal && (
        <div className="modal-backdrop">
          <div className="modal-card">
            <h2>Recommended: add Hugging Face key</h2>
            <p>Insert your HF token now for smoother model downloads and fewer auth errors later.</p>
            <input
              className="hf-input"
              type="password"
              placeholder="hf_xxxxxxxxxxxxxxxxx"
              value={hfKey}
              onChange={(e) => setHfKey(e.target.value)}
            />
            <div className="modal-actions">
              <button className="modal-btn primary" onClick={saveHfKey}>
                Save key
              </button>
              <button className="modal-btn" onClick={() => setShowHfModal(false)}>
                Skip for now
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="home-wrap">
        <header className="topbar">
          <div className="brand">FEDDA Hub</div>
          <div className="status-row">
            <button className="metric-chip token-chip" onClick={() => setShowHfModal(true)}>
              HF Key
            </button>
            <span className={statusClass}>{status.connected ? "ComfyUI Connected" : "ComfyUI Offline"}</span>
            <span className="metric-chip">VRAM {status.vramText}</span>
            <span className="metric-chip">RAM {status.ramText}</span>
          </div>
        </header>
        {renderSection()}
      </div>
    </main>
  );
}
