.PHONY: env env-update doctor doctor-conectado

env:
	conda env create -f environment.yml

env-update:
	conda env update -f environment.yml --prune

doctor:
	@bash scripts/doctor.sh offline

doctor-conectado:
	@bash scripts/doctor.sh conectado
