import express from "express";
import dotenv from "dotenv";
import { IntentSchema } from "./schema";
import { Anthropic } from "@anthropic-ai/sdk";

dotenv.config();

const app = express();
app.use(express.json());

const port = process.env.PORT || 3001;
const anthropicKey = process.env.ANTHROPIC_API_KEY || "";
const client = anthropicKey ? new Anthropic({ apiKey: anthropicKey }) : null;

// Simple decompose endpoint — calls Anthropic if key present, otherwise returns a sample.
app.post('/decompose', async (req, res) => {
  const { text } = req.body;
  if (!text || typeof text !== 'string') return res.status(400).send({ error: 'text required' });

  try {
    if (client) {
      // Example: call Claude to decompose; production code should handle prompt engineering and safety.
      const completion = await client.completions.create({
        model: 'claude-2',
        prompt: `Decompose the following user intent into structured JSON segments and watchers:\n\n${text}`,
        max_tokens: 500,
      });
      const output = completion?.completion || '';
      // Naively attempt to parse JSON from completion
      const start = output.indexOf('{');
      const json = start >= 0 ? output.slice(start) : output;
      try {
        const parsed = JSON.parse(json);
        const validated = IntentSchema.parse(parsed);
        return res.json({ ok: true, intent: validated });
      } catch (err) {
        return res.json({ ok: false, error: 'failed to parse/comprehend AI response', raw: output });
      }
    }

    // Fallback sample response
    const sample = {
      text,
      segments: [{ type: 'SWAP', data: { from: 'ETH', to: 'USDC', amount: '1' } }],
      watchers: [{ type: 'PRICE', params: { symbol: 'ETH', condition: '<2000' } }]
    };
    const validated = IntentSchema.parse(sample);
    res.json({ ok: true, intent: validated });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err) });
  }
});

app.listen(port, () => {
  console.log(`Sigil backend listening on ${port}`);
});
