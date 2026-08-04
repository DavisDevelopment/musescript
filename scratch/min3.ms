strategy Min3 { onBar { when min(close + 2, close, close + 1) == close: long() when min(close+2,close,close+1) > close: flat() } }
