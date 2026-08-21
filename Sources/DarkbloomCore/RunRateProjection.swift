import Foundation

public enum RunRateProjection {
    /// Forecasts the current hour's final total without treating its partial
    /// annualized rate as equally trustworthy throughout the hour.
    ///
    /// Recent completed hours form an exponentially weighted prior. The
    /// partial hour is a Kalman-style measurement whose noise falls toward
    /// zero as the hour completes, so the estimate is stable early and exactly
    /// converges to the observed total at the boundary.
    public static func projectedTotal(
        completedTotals: [Double],
        currentTotal: Double,
        elapsedFraction: Double,
        smoothing: Double = 0.35
    ) -> Double {
        let current = max(0, currentTotal)
        guard !completedTotals.isEmpty else { return current }

        let values = completedTotals.map { max(0, $0) }
        let alpha = min(1, max(0.01, smoothing))
        var prior = values[0]
        for value in values.dropFirst() {
            prior = alpha * value + (1 - alpha) * prior
        }

        let mean = values.reduce(0, +) / Double(values.count)
        let observedVariance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        let scaleFloor = pow(max(1, prior * 0.25), 2)
        let priorVariance = max(observedVariance, scaleFloor)

        // Treat the first minute as the minimum observation interval so a
        // request arriving seconds after the hour doesn't imply an enormous
        // instantaneous rate.
        let fraction = min(1, max(1.0 / 60.0, elapsedFraction))
        let annualizedMeasurement = current / fraction
        let remaining = 1 - fraction
        let measurementVariance = priorVariance * remaining * remaining / fraction
        let gain = priorVariance / (priorVariance + measurementVariance)
        let estimate = prior + gain * (annualizedMeasurement - prior)
        return max(current, estimate)
    }
}
