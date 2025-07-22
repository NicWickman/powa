const express = require("express");
const cors = require("cors");
const fs = require("fs").promises;
const path = require("path");
const { spawn } = require("child_process");

const app = express();
const PORT = process.env.PORT || 3000;

// Track active processes for cleanup
const activeProcesses = new Set();

// Middleware
app.use(cors());
app.use(express.json({ limit: "1mb" })); // Limit request size
app.use(express.static("."));

// Serve the HTML file
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "powa-model.html"));
});

// Run forge test endpoint with better cleanup
app.post("/run-test", async (req, res) => {
  let forgeTest = null;
  let timeoutId = null;

  try {
    const config = req.body;

    // Validate config
    if (
      !config.revenueAmount ||
      !config.epochs ||
      !Array.isArray(config.epochs)
    ) {
      return res.status(400).json({ error: "Invalid configuration format" });
    }

    // Validate reasonable limits
    if (config.epochs.length > 20) {
      return res.status(400).json({ error: "Too many epochs (max 20)" });
    }

    if (config.revenueAmount > 1e12) {
      return res.status(400).json({ error: "Revenue amount too large" });
    }

    // Ensure test directory exists
    const testDir = path.join(__dirname, "test");
    await fs.mkdir(testDir, { recursive: true });

    // Write config to file
    const configPath = path.join(testDir, "powa-config.json");
    await fs.writeFile(configPath, JSON.stringify(config, null, 2));

    // Set up SSE (Server-Sent Events) for streaming output
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no", // Disable Nginx buffering
    });

    // Send initial heartbeat
    res.write(
      `data: ${JSON.stringify({
        type: "start",
        message: "Starting forge test...",
      })}\n\n`,
    );

    // Run forge test
    forgeTest = spawn(
      "forge",
      [
        "test",
        "--match-contract",
        "ParameterizedPOWATest",
        "--match-test",
        config.userHoldings ? "testScenario" : "testDistribution",
        "-vvv",
      ],
      {
        cwd: __dirname,
        shell: true,
        env: { ...process.env, FORCE_COLOR: "0" }, // Disable color output for cleaner logs
      },
    );

    // Track the process
    activeProcesses.add(forgeTest);

    // Set timeout (60 seconds)
    timeoutId = setTimeout(() => {
      if (forgeTest && !forgeTest.killed) {
        forgeTest.kill("SIGTERM");
        res.write(
          `data: ${JSON.stringify({
            type: "error",
            error: "Test timeout after 60 seconds",
          })}\n\n`,
        );
        res.end();
      }
    }, 60000);

    // Handle client disconnect
    req.on("close", () => {
      if (forgeTest && !forgeTest.killed) {
        console.log("Client disconnected, killing forge process");
        forgeTest.kill("SIGTERM");
      }
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
    });

    // Stream stdout
    forgeTest.stdout.on("data", (data) => {
      const lines = data.toString().split("\n");
      lines.forEach((line) => {
        if (line.trim()) {
          try {
            res.write(
              `data: ${JSON.stringify({ type: "stdout", data: line })}\n\n`,
            );
          } catch (e) {
            // Client might have disconnected
            console.error("Failed to write stdout:", e.message);
          }
        }
      });
    });

    // Stream stderr
    forgeTest.stderr.on("data", (data) => {
      const lines = data.toString().split("\n");
      lines.forEach((line) => {
        if (line.trim()) {
          try {
            res.write(
              `data: ${JSON.stringify({ type: "stderr", data: line })}\n\n`,
            );
          } catch (e) {
            // Client might have disconnected
            console.error("Failed to write stderr:", e.message);
          }
        }
      });
    });

    // Handle process completion
    forgeTest.on("close", (code) => {
      activeProcesses.delete(forgeTest);
      if (timeoutId) {
        clearTimeout(timeoutId);
      }

      try {
        res.write(`data: ${JSON.stringify({ type: "complete", code })}\n\n`);
        res.end();
      } catch (e) {
        // Client might have already disconnected
        console.error("Failed to send completion:", e.message);
      }
    });

    // Handle errors
    forgeTest.on("error", (error) => {
      activeProcesses.delete(forgeTest);
      if (timeoutId) {
        clearTimeout(timeoutId);
      }

      console.error("Forge process error:", error);
      try {
        res.write(
          `data: ${JSON.stringify({
            type: "error",
            error: error.message,
          })}\n\n`,
        );
        res.end();
      } catch (e) {
        // Client might have already disconnected
        console.error("Failed to send error:", e.message);
      }
    });
  } catch (error) {
    console.error("Error in /run-test:", error);

    // Clean up process if it exists
    if (forgeTest && !forgeTest.killed) {
      forgeTest.kill("SIGTERM");
      activeProcesses.delete(forgeTest);
    }

    if (timeoutId) {
      clearTimeout(timeoutId);
    }

    // Try to send error response
    if (!res.headersSent) {
      res.status(500).json({ error: error.message });
    } else {
      try {
        res.write(
          `data: ${JSON.stringify({
            type: "error",
            error: error.message,
          })}\n\n`,
        );
        res.end();
      } catch (e) {
        // Client disconnected
      }
    }
  }
});

// Health check endpoint
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    message: "POWA dev server is running",
    activeTests: activeProcesses.size,
  });
});

// Start server
const server = app.listen(PORT, () => {
  console.log(`POWA dev server running at http://localhost:${PORT}`);
  console.log("\nPress Ctrl+C to stop the server");
});

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  console.log(`\n${signal} received, shutting down gracefully...`);

  // Stop accepting new connections
  server.close(() => {
    console.log("HTTP server closed");
  });

  // Kill any active forge processes
  if (activeProcesses.size > 0) {
    console.log(`Terminating ${activeProcesses.size} active test(s)...`);
    activeProcesses.forEach((proc) => {
      if (!proc.killed) {
        proc.kill("SIGTERM");
      }
    });
  }

  // Give processes time to clean up
  setTimeout(() => {
    console.log("Shutdown complete");
    process.exit(0);
  }, 1000);
};

// Handle shutdown signals
process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));

// Handle uncaught errors
process.on("uncaughtException", (error) => {
  console.error("Uncaught Exception:", error);
  gracefulShutdown("UNCAUGHT_EXCEPTION");
});

process.on("unhandledRejection", (reason, promise) => {
  console.error("Unhandled Rejection at:", promise, "reason:", reason);
});
