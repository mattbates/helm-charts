# publish.sh - publish Helm chart packages to Cloudflare Pages
#!/bin/bash

set -eux

if ! command -v helm &> /dev/null; then
    echo "Installing Helm"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod +x get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
else
    echo "Helm already installed: $(helm version --short)"
fi

echo "Creating output directory"
mkdir -p dist

echo "Processing Helm charts"
for chart in charts/*/; do
    if [ -f "$chart/Chart.yaml" ]; then
        echo "Processing chart: $chart"
        cd "$chart"
        
        # Update dependencies if Chart.lock exists
        if [ -f "Chart.lock" ]; then
            helm dependency update
        fi
        
        cd - > /dev/null
        
        # Package the chart
        echo "Packaging chart: $chart"
        helm package "$chart" --destination dist/
    fi
done

echo "Generating Helm repository index"
REPO_URL=${CF_PAGES_URL:-"http://localhost:8080"}
helm repo index dist/ --url $CF_PAGES_URL

echo "Creating index.html"
cat > dist/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Helm Chart Repository</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0; padding: 40px; background: #f8fafc; 
        }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .header { border-bottom: 2px solid #e2e8f0; padding-bottom: 20px; margin-bottom: 30px; }
        .header h1 { margin: 0; color: #1a202c; }
        .header p { margin: 10px 0 0 0; color: #718096; }
        .usage { background: #f7fafc; border: 1px solid #e2e8f0; padding: 20px; margin: 20px 0; border-radius: 6px; }
        .usage h3 { margin-top: 0; color: #2d3748; }
        code { 
            background: #edf2f7; padding: 4px 8px; border-radius: 4px; 
            font-family: 'Monaco', 'Consolas', monospace; font-size: 14px; 
        }
        .command-block { background: #2d3748; color: #e2e8f0; padding: 15px; border-radius: 6px; margin: 10px 0; }
        .command-block code { background: transparent; color: #68d391; }
        #chart-list { list-style: none; padding: 0; }
        #chart-list li { padding: 10px; margin: 5px 0; background: #f7fafc; border-radius: 4px; border-left: 4px solid #4299e1; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #e2e8f0; color: #718096; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎯 Helm Chart Repository</h1>
            <p>Public Helm charts repository hosted on Cloudflare Pages</p>
        </div>
        
        <div class="usage">
            <h3>📦 Quick Start</h3>
            <p>Add this repository to your Helm installation:</p>
            <div class="command-block">
                <code>helm repo add myrepo <span id="repo-url"></span></code><br>
                <code>helm repo update</code>
            </div>
        </div>
        
        <h2>📋 Available Charts</h2>
        <ul id="chart-list">
            <li>Loading charts...</li>
        </ul>
        
        <div class="usage">
            <h3>🔍 Chart Information</h3>
            <p>View the complete repository index:</p>
            <div class="command-block">
                <code><a href="index.yaml" style="color: #68d391;">index.yaml</a></code>
            </div>
        </div>

        <div class="footer">
            <p>Repository automatically updated via Cloudflare Pages • <a href="https://helm.sh">Helm Documentation</a></p>
        </div>
    </div>
    
    <script>
        // Set the repository URL
        document.getElementById('repo-url').textContent = window.location.origin;
        
        // Load and display charts
        fetch('index.yaml')
            .then(response => response.text())
            .then(data => {
                const chartList = document.getElementById('chart-list');
                chartList.innerHTML = '';
                
                const charts = new Map();
                const lines = data.split('\n');
                let currentChart = null;
                
                lines.forEach(line => {
                    const trimmed = line.trim();
                    if (trimmed.startsWith('- name:')) {
                        currentChart = trimmed.split(':')[1].trim();
                        if (!charts.has(currentChart)) {
                            charts.set(currentChart, { versions: [], description: '' });
                        }
                    } else if (currentChart && trimmed.startsWith('version:')) {
                        const version = trimmed.split(':')[1].trim();
                        charts.get(currentChart).versions.push(version);
                    } else if (currentChart && trimmed.startsWith('description:')) {
                        const desc = trimmed.split(':')[1].trim();
                        charts.get(currentChart).description = desc;
                    }
                });
                
                if (charts.size === 0) {
                    chartList.innerHTML = '<li>No charts available yet</li>';
                    return;
                }
                
                charts.forEach((info, chartName) => {
                    const li = document.createElement('li');
                    const latestVersion = info.versions[0] || 'unknown';
                    li.innerHTML = `
                        <strong>${chartName}</strong> 
                        <span style="color: #4299e1; font-size: 12px;">(${latestVersion})</span>
                        ${info.description ? `<br><small style="color: #718096;">${info.description}</small>` : ''}
                    `;
                    chartList.appendChild(li);
                });
            })
            .catch(err => {
                console.error('Error loading charts:', err);
                document.getElementById('chart-list').innerHTML = '<li>Error loading chart information</li>';
            });
    </script>
</body>
</html>
EOF

echo "Build completed successfully"
echo "Charts packaged: $(ls -1 dist/*.tgz 2>/dev/null | wc -l)"
