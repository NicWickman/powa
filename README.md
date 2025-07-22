# POWA Revenue Distribution Model

POWA smart contracts and interactive web interface for testing and modeling POWA token revenue distribution across multiple epochs.

## Features

- 🎮 Interactive web UI for configuring epochs and revenue distribution
- 🧪 Automated Forge test generation and execution
- 📊 Calculation of revenue distribution across epochs
- 💰 User holdings calculator to preview claimable revenue
- ✅ Invariant checking to ensure complete distribution

## Prerequisites

- Node.js (v14 or higher)
- npm
- Git
- Foundry (for Forge)

## Installation

### 1. Install Foundry (Forge)

```bash
# On macOS/Linux
curl -L https://foundry.paradigm.xyz | bash
foundryup

# On Windows (using Git Bash)
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

Verify installation:

```bash
forge --version
```

### 2. Clone the Repository

```bash
git clone <your-repo-url>
cd powa
```

### 3. Install Dependencies

Install Solidity dependencies:

```bash
forge install
```

Install Node.js dependencies:

```bash
npm install
```

## Starting the Development Server

1. Start the local dev server:

```bash
npm start
# or
node powa-server.js
```

2. Open your browser and navigate to:

```
http://localhost:3000
```

## Using the Demo

### 1. Configure Epochs

In the web interface:

- **Set Total Revenue**: Enter the amount of revenue to distribute (e.g., 10000000)
- **Configure Epochs**: Each epoch has:
  - **iPOWA Tokens**: Amount of investor tokens
  - **cPOWA Tokens**: Amount of contributor tokens
  - **Weight**: Relative weight for distribution (1.0 = 100%, 0.5 = 50%)
- **Add/Remove Epochs**: Use the "+ Add Epoch" button or X to remove

### 2. View Distribution Results

The interface automatically calculates:

- Revenue per epoch based on weighted supply
- Revenue per token type (iPOWA/cPOWA)
- Distribution percentages

### 3. Calculate User Holdings (Optional)

Enter token holdings to see claimable revenue:

- Input iPOWA and cPOWA holdings for each epoch
- View total claimable revenue
- See breakdown by epoch and token type

### 4. Run Forge Tests

Click the **"🔨 Run Forge Test"** button to:

- Generate a test configuration based on your inputs
- Execute the test on local forge chain
- View test output in the terminal window

The test will:

- Deploy mock tokens and distributor contracts
- Create epochs with your configuration
- Distribute revenue
- Verify the distribution matches calculations
- Test user claims if holdings were specified

## Understanding the Output

### Distribution Results

- **Weighted Supply**: Token supply × epoch weight
- **Epoch Revenue**: Proportional share based on weighted supply
- **Revenue per Token**: Epoch revenue ÷ total tokens

### Invariant Check

Shows that total distributed equals deposited amount (may have 1-2 wei dust proportional to number of epochs)

## Configuration File

The test automatically generates `test/powa-config.json`:

```json
{
  "revenueAmount": 10000000,
  "epochs": [
    {
      "iPOWA": 2000000,
      "cPOWA": 3000000,
      "weight": 10000
    }
  ],
  "userHoldings": {
    "0": {
      "iPOWA": 100000,
      "cPOWA": 50000
    }
  }
}
```

## Troubleshooting

### "Failed to run test"

Make sure the dev server is running (`npm start`)

### "forge: command not found"

Ensure Foundry is installed and in your PATH:

```bash
source ~/.bashrc  # or ~/.zshrc
forge --version
```

### Port 3000 already in use

Change the port in `powa-server.js`:

```javascript
const PORT = 3001; // or any available port
```

## Project Structure

```
powerhouse/pow/
├── src/
│   ├── Distributor.sol      # Revenue distributor contract
│   └── token/
│       ├── iPOWA.sol        # Investor token
│       └── cPOWA.sol        # Contributor token
├── test/
│   ├── ParameterizedPOWATest.sol  # Forge test
│   └── powa-config.json           # Generated config
├── powa-model.html          # Web interface
├── powa-server.js           # Dev server
├── package.json             # Node dependencies
└── foundry.toml             # Forge configuration
```

## Security

This development server is for local testing only. Never expose it to the internet as it executes system commands based on user input.

## Disclaimer

This software is distributed as-is and without liability or promise or guarantee of anything ever anywhere.
