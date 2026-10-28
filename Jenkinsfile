pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds(); timeout(time: 30, unit: 'MINUTES') }
  environment {
    IMAGE = 'inventory-api'
    CANDIDATE = 'inventory-candidate'
    LIVE = 'inventory-live'
  }
  stages {
    stage('Checkout') {
      steps { checkout scm; sh 'git rev-parse --short HEAD' }
    }
    stage('Unit tests') {
      steps {
        sh '''
          set -eu
          python3 -m venv .venv
          .venv/bin/pip install -r requirements-dev.txt
          mkdir -p reports
          .venv/bin/python -m pytest -v --junitxml=reports/pytest.xml
        '''
      }
    }
    stage('Static check') {
      steps { sh '.venv/bin/ruff check app tests' }
    }
    stage('Build image') {
      steps {
        sh '''
          set -eu
          docker build -t "$IMAGE:$BUILD_NUMBER" .
        '''
      }
    }
    stage('Container smoke test') {
      steps {
        sh '''
          set -eu
          docker rm -f "$CANDIDATE" >/dev/null 2>&1 || true
          docker run -d --name "$CANDIDATE" -p 127.0.0.1:5051:5000 "$IMAGE:$BUILD_NUMBER"
          ready=0
          for i in $(seq 1 20); do
            if curl -fsS http://127.0.0.1:5051/health | grep -q '"status":"ok"'; then ready=1; break; fi
            sleep 1
          done
          test "$ready" -eq 1
          curl -fsS http://127.0.0.1:5051/api/items | grep -q 'router'
        '''
      }
    }
    stage('Deploy locally') {
      steps {
        sh 'sh scripts/deploy_local.sh "$IMAGE:$BUILD_NUMBER"'
      }
    }
  }
  post {
    always {
      sh 'docker rm -f inventory-candidate >/dev/null 2>&1 || true'
      junit allowEmptyResults: true, testResults: 'reports/pytest.xml'
      archiveArtifacts artifacts: 'reports/*.xml', allowEmptyArchive: true
    }
  }
}
