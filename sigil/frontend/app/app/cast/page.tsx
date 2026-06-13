'use client';

import { useState, useEffect } from 'react';
import { PresetIntents } from '../../../components/intent/PresetIntents';
import { IntentInput } from '../../../components/intent/IntentInput';
import { DecompositionView } from '../../../components/intent/DecompositionView';
import { ConfirmIntent } from '../../../components/intent/ConfirmIntent';
import { useSigilStore } from '../../../stores/sigil';
import { useDecompose } from '../../../hooks/useDecompose';
import { SigilLogo } from '../../../components/layout/SigilLogo';

// Step indicator
function StepIndicator({ current }: { current: number }) {
  const steps = ['Describe', 'Review', 'Confirm', 'Done'];
  return (
    <div className="flex items-center gap-2 mb-8">
      {steps.map((label, i) => (
        <div key={label} className="flex items-center gap-2">
          <div className={`flex items-center gap-1.5 text-xs ${i === current ? 'text-amethyst-400' : i < current ? 'text-emerald-400' : 'text-text-tertiary'}`}>
            <div className={`w-5 h-5 rounded-full border flex items-center justify-center text-[10px] font-bold
              ${i === current ? 'border-amethyst-500/50 bg-amethyst-900/30 text-amethyst-400' :
                i < current ? 'border-emerald-500/30 bg-emerald-900/20 text-emerald-400' :
                'border-white/10 bg-sigil-tertiary text-text-tertiary'}`}
            >
              {i < current ? '✓' : i + 1}
            </div>
            {label}
          </div>
          {i < steps.length - 1 && (
            <div className={`h-px w-6 ${i < current ? 'bg-emerald-500/30' : 'bg-white/10'}`} />
          )}
        </div>
      ))}
    </div>
  );
}

export default function CastPage() {
  // Set browser page title
  useEffect(() => {
    document.title = 'Cast Sigil | Sigil';
  }, []);

  const { intentText, intentStep, decomposed, intentError, setIntentText, setIntentStep, resetIntent } = useSigilStore();
  const { decompose, isLoading } = useDecompose();
  const [stepIndex, setStepIndex] = useState(0);

  const handlePreset = (text: string) => {
    setIntentText(text);
  };

  const handleDecompose = () => {
    setStepIndex(1);
    decompose(intentText);
  };

  const handleConfirm = () => {
    setStepIndex(2);
    setIntentStep('confirming');
  };

  const handleReset = () => {
    setStepIndex(0);
    resetIntent();
  };

  const handleSuccess = () => {
    setStepIndex(3);
  };

  const showInput = intentStep === 'idle' || intentStep === 'loading' || intentStep === 'error';
  const showDecomposed = intentStep === 'decomposed';
  const showConfirm = intentStep === 'confirming' || intentStep === 'executing';
  const showDone = intentStep === 'done';

  return (
    <div className="max-w-2xl mx-auto">
      {/* Header */}
      <div className="flex items-center gap-3 mb-2">
        <h1 className="font-display text-2xl text-text-primary">Cast a Sigil</h1>
      </div>
      <p className="text-text-tertiary text-sm mb-8">
        Describe your intent in plain English. The AI will decompose it into on-chain segments and persistent watchers.
      </p>

      <StepIndicator current={showDone ? 3 : showConfirm ? 2 : showDecomposed ? 1 : 0} />

      {/* Step: Input */}
      {showInput && (
        <div className="space-y-6 animate-fade-up">
          <IntentInput
            value={intentText}
            onChange={setIntentText}
            onSubmit={handleDecompose}
            isLoading={isLoading}
          />

          {intentError && (
            <div className="p-3 rounded-xl border border-ruby-500/20 bg-ruby-900/20 text-xs text-ruby-400">
              ⚠ {intentError}
            </div>
          )}

          {/* Preset templates */}
          {!isLoading && (
            <div>
              <p className="text-xs text-text-tertiary mb-3">Or choose a preset template:</p>
              <PresetIntents onSelect={handlePreset} />
            </div>
          )}
        </div>
      )}

      {/* Step: Decomposition review */}
      {showDecomposed && decomposed && (
        <DecompositionView
          decomposed={decomposed}
          onConfirm={handleConfirm}
          onReset={handleReset}
          isConfirming={false}
        />
      )}

      {/* Step: Confirm + broadcast */}
      {showConfirm && decomposed && (
        <ConfirmIntent
          decomposed={decomposed}
          onSuccess={handleSuccess}
          onCancel={() => {
            setStepIndex(1);
            setIntentStep('decomposed');
          }}
        />
      )}

      {/* Step: Done */}
      {showDone && (
        <div className="flex flex-col items-center justify-center py-16 text-center animate-fade-up">
          <SigilLogo size={64} animate />
          <h2 className="font-display text-3xl text-text-primary mt-6 mb-2">Sigil Active</h2>
          <p className="text-text-secondary text-sm mb-8 max-w-sm">
            Your intent is now inscribed on-chain. The watchers are live and monitoring.
          </p>
          <button
            onClick={handleReset}
            className="px-6 py-3 rounded-xl text-sm font-medium border border-white/10 text-text-secondary hover:border-amethyst-500/30 hover:text-text-primary transition-all"
          >
            Cast another Sigil
          </button>
        </div>
      )}
    </div>
  );
}
