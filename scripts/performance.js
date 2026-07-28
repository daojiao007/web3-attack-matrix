import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate } from "k6/metrics";

const rpcDuration = new Trend("eth_rpc_duration", true);
const errorRate = new Rate("error_rate");
const RPC_URL = __ENV.RPC_URL || "http://localhost:8545";

const BODY = JSON.stringify({
  jsonrpc: "2.0",
  method: "eth_blockNumber",
  params: [],
  id: 1,
});

const PARAMS = { headers: { "Content-Type": "application/json" } };

export const options = {
  scenarios: {
    normal: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: "10s", target: 50 },
        { duration: "30s", target: 50 },
        { duration: "10s", target: 0 },
      ],
      exec: "callRPC",
    },
    spike: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: "5s", target: 200 },
        { duration: "20s", target: 200 },
        { duration: "5s", target: 0 },
      ],
      startTime: "50s",
      exec: "callRPC",
    },
    soak: {
      executor: "constant-vus",
      vus: 100,
      duration: "60s",
      startTime: "80s",
      exec: "callRPC",
    },
  },
  thresholds: {
    error_rate: ["rate < 0.01"],
  },
};

export function callRPC() {
  const start = Date.now();
  const res = http.post(RPC_URL, BODY, PARAMS);
  rpcDuration.add(Date.now() - start);

  const ok = check(res, {
    "status 200": (r) => r.status === 200,
    "has result": (r) => {
      try { return JSON.parse(r.body).result !== undefined; }
      catch { return false; }
    },
  });

  errorRate.add(!ok);
  sleep(0.1);
}

export function teardown() {
  console.log("\n===== K6 Done =====");
  console.log(`RPC: ${RPC_URL}`);
}
