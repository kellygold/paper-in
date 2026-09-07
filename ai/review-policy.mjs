// Return actionable reasons separately from the model's description of the document.
export function reviewReasons(first, second, document, context) {
  const reasons = [];
  if (first.needsReview || second.needsReview) reasons.push('The AI requested a human check.');
  if (first.folder !== second.folder || first.filename !== second.filename)
    reasons.push('The two checks proposed different names or folders.');
  if (document.lowConfidence || document.lowText) reasons.push('Some receipt text was hard to read.');
  if (document.truncated || context.limited) reasons.push('Only part of the document or filing library could be checked.');
  if (context.duplicate || [...first.related, ...second.related].some(r => r.relationship !== 'same_vendor'))
    reasons.push('Check whether the related document is a duplicate or another page of this document.');
  if (!context.folders.includes(second.folder)) reasons.push('Confirm creation of a new folder.');
  if (Math.min(first.confidence, second.confidence) < 0.92) reasons.push('The suggested filing location is uncertain.');
  return reasons;
}
