// 验证 eventually() 的行为——模拟索引器延迟写入

import { eventually } from "./eventually";

async function main() {
  // === 测试 1: 正常等到数据 ===
  console.log("Test 1: wait for data...");
  let ready = false;
  setTimeout(() => { ready = true; }, 2000); // 2s 后数据就绪

  const result = await eventually(
    async () => (ready ? 42 : null),
    { interval: 500 }
  );
  console.assert(result === 42, "Test 1 PASSED: got 42");
  console.log("  ✅ Test 1 passed");

  // === 测试 2: 超时报错 ===
  console.log("Test 2: timeout...");
  try {
    await eventually(
      async () => null, // 永远不 ready
      { timeout: 1000, interval: 200 }
    );
    console.assert(false, "Should have thrown");
  } catch (e: any) {
    console.assert(e.message.includes("timed out"), "Test 2 PASSED: threw timeout");
    console.log("  ✅ Test 2 passed");
  }

  // === 测试 3: 立刻返回 ===
  console.log("Test 3: immediate...");
  const r = await eventually(async () => "instant");
  console.assert(r === "instant", "Test 3 PASSED");
  console.log("  ✅ Test 3 passed");
}

main();
