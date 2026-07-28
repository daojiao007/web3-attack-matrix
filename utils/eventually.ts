/**
 * 异步轮询——直到条件满足或超时
 *
 * @param check  返回 null = 还没好，返回 T = 拿到了
 * @param options.timeout  超时 ms（默认 30000）
 * @param options.interval 初始间隔 ms（默认 1000，每次翻倍）
 * @returns Promise<T>
 */
export async function eventually<T>(
  check: () => Promise<T | null>,
  options: { timeout?: number; interval?: number } = {}
): Promise<T> {
  const timeout = options.timeout ?? 30000;
  const start = Date.now();
  let delay = options.interval ?? 1000;

  while (true) {
    const result = await check();
    if (result !== null) {
      return result;
    }

    if (Date.now() - start >= timeout) {
      throw new Error(`eventually() timed out after ${timeout}ms`);
    }

    await sleep(delay);
    delay = Math.min(delay * 2, 10000);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
