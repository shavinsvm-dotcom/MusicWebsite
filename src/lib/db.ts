/** Tiny promise wrapper over IndexedDB — no dependencies, no schema churn. */

const DB_NAME = "nocturne";
const DB_VERSION = 1;
const STORE_UPLOADS = "uploads";
const STORE_KV = "kv";

let dbPromise: Promise<IDBDatabase> | null = null;

function openDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_UPLOADS)) db.createObjectStore(STORE_UPLOADS, { keyPath: "id" });
      if (!db.objectStoreNames.contains(STORE_KV)) db.createObjectStore(STORE_KV);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error("IndexedDB unavailable"));
  });
  return dbPromise;
}

function tx<T>(store: string, mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return openDb().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const transaction = db.transaction(store, mode);
        const request = fn(transaction.objectStore(store));
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error ?? new Error("IndexedDB request failed"));
      }),
  );
}

export type StoredUpload = {
  id: string;
  title: string;
  artist: string;
  album: string;
  genre: string;
  lyrics?: string;
  duration: number;
  art?: string;
  cover: { from: string; to: string; accent: string; glyph?: string };
  createdAt: number;
  plays: number;
  size: number;
  mime: string;
  blob: Blob;
};

export const idb = {
  allUploads: () => tx<StoredUpload[]>(STORE_UPLOADS, "readonly", (s) => s.getAll() as IDBRequest<StoredUpload[]>),
  putUpload: (row: StoredUpload) => tx(STORE_UPLOADS, "readwrite", (s) => s.put(row)),
  deleteUpload: (id: string) => tx(STORE_UPLOADS, "readwrite", (s) => s.delete(id)),
  get: <T,>(key: string) => tx<T | undefined>(STORE_KV, "readonly", (s) => s.get(key) as IDBRequest<T | undefined>),
  set: (key: string, value: unknown) => tx(STORE_KV, "readwrite", (s) => s.put(value, key)),
};
