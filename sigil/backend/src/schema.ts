import { z } from "zod";

export const SegmentType = z.enum(["SWAP", "DEPOSIT", "WITHDRAW", "HEDGE"]);
export const WatcherType = z.enum(["PRICE", "GOVERNANCE", "RISK", "TIME"]);

export const IntentSchema = z.object({
  id: z.string().optional(),
  owner: z.string().optional(),
  text: z.string(),
  segments: z.array(z.object({ type: SegmentType, data: z.any() })),
  watchers: z.array(z.object({ type: WatcherType, params: z.any() })).optional(),
});

export type Intent = z.infer<typeof IntentSchema>;
