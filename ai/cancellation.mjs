const controller = new AbortController();
export const workerSignal = controller.signal;
export const cancelWorker = () => controller.abort();
