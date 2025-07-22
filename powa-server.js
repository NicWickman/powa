const cors = require("cors");
const fs = require("fs").promises;
const path = require("path");
const { spawn } = require("child_process");

const app = express();
const PORT = 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static("."));

// Serve the HTML file
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "powa-model.html"));
});

// Run forge test endpoint
app.post("/run-test", async (req, res) => {
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

    // Write config to file
    const configPath = path.join(__dirname, "test", "powa-config.json");
    await fs.writeFile(configPath, JSON.stringify(config, null, 2));

    // Set up SSE (Server-Sent Events) for streaming output
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });

    // Run forge test
    const forgeTest = spawn(
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
      },
    );

    // Stream stdout
    forgeTest.stdout.on("data", (data) => {
      const lines = data.toString().split("\n");
      lines.forEach((line) => {
        if (line.trim()) {
          res.write(
            `data: ${JSON.stringify({ type: "stdout", data: line })}\n\n`,
          );
        }
      });
    });

    // Stream stderr
    forgeTest.stderr.on("data", (data) => {
      const lines = data.toString().split("\n");
      lines.forEach((line) => {
        if (line.trim()) {
          res.write(
            `data: ${JSON.stringify({ type: "stderr", data: line })}\n\n`,
          );
        }
      });
    });

    // Handle process completion
    forgeTest.on("close", (code) => {
      res.write(`data: ${JSON.stringify({ type: "complete", code })}\n\n`);
      res.end();
    });

    // Handle errors
    forgeTest.on("error", (error) => {
      res.write(
        `data: ${JSON.stringify({ type: "error", error: error.message })}\n\n`,
      );
      res.end();
    });
  } catch (error) {
    console.error("Error:", error);
    res.status(500).json({ error: error.message });
  }
});

// Health check endpoint
app.get("/health", (req, res) => {
  res.json({ status: "ok", message: "POWA dev server is running" });
});

app.listen(PORT, () => {
  console.log(`POWA dev server running at http://localhost:${PORT}`);
  console.log("\nMake sure you have:");
  console.log("1. Forge installed and in your PATH");
  console.log('2. Run "npm install express cors" if you haven\'t already');
  console.log("\nPress Ctrl+C to stop the server");
});
