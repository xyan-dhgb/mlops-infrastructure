import { useState, useCallback } from 'react'
import ImageUpload from './components/ImageUpload'
import TabularForm from './components/TabularForm'
import ResultDisplay from './components/ResultDisplay'
import './App.css'

// Default: relative URL for Nginx reverse proxy in cluster
// Fallback: localhost:8080 for local dev with port-forward
const DEFAULT_API = '/api'

export default function App() {
  const [imageBase64, setImageBase64] = useState(null)
  const [tabularRaw, setTabularRaw] = useState({})
  const [result, setResult] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)

  const predict = useCallback(async () => {
    if (!imageBase64) return

    setLoading(true)
    setResult(null)
    setError(null)

    try {
      const body = {
        instances: [{
          image: imageBase64,
          tabular_raw: tabularRaw,
        }],
      }

      const res = await fetch(`${DEFAULT_API}/v1/models/skin-prediction:predict`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(120000), // 2 min timeout for cold start
      })

      if (!res.ok) {
        const text = await res.text()
        throw new Error(`HTTP ${res.status}: ${text}`)
      }

      const data = await res.json()
      setResult(data.predictions[0])
    } catch (err) {
      setError(err.message || 'Không thể kết nối đến mô hình')
    } finally {
      setLoading(false)
    }
  }, [imageBase64, tabularRaw])

  return (
    <div className="app">

      {/* ===== Hero Section (Dark) ===== */}
      <section className="section-dark hero" id="hero-section">
        <div className="container hero__inner">
          <h1 className="hero-display hero__headline">
            Chẩn đoán<br />Ung thư Da
          </h1>
          <p className="lead hero__subtitle">
            Mô hình đa phương thức kết hợp hình ảnh da liễu và dữ liệu lâm sàng
          </p>
        </div>
      </section>

      {/* ===== Main Content (Parchment) ===== */}
      <section className="section-parchment" id="main-section">
        <div className="container main-grid">

          {/* Left column — Inputs */}
          <div className="main-col main-col--input">

            {/* Image Upload */}
            <div className="card" id="card-image">
              <p className="tagline card__title">Ảnh tổn thương</p>
              <ImageUpload onImageSelect={setImageBase64} />
            </div>

            {/* Tabular Form */}
            <div className="card" id="card-tabular">
              <p className="tagline card__title">Dữ liệu lâm sàng</p>
              <TabularForm onTabularChange={setTabularRaw} />
            </div>

            {/* Predict Button */}
            <button
              className="btn-primary predict-btn"
              onClick={predict}
              disabled={!imageBase64 || loading}
              id="btn-predict"
            >
              {loading ? 'Đang phân tích...' : 'Dự đoán'}
            </button>
          </div>

          {/* Right column — Result */}
          <div className="main-col main-col--result">
            <div className="card result-card" id="card-result">
              <p className="tagline card__title">Kết quả</p>
              <ResultDisplay result={result} loading={loading} error={error} />
            </div>
          </div>
        </div>
      </section>

      {/* ===== Footer ===== */}
      <footer className="app-footer" id="app-footer">
        <div className="container">
          <p className="fine-print">
            Hệ thống hỗ trợ chẩn đoán không thay thế ý kiến bác sĩ chuyên khoa.
            Dữ liệu huấn luyện từ ISIC 2024 Challenge.
          </p>
        </div>
      </footer>
    </div>
  )
}
