import pydantic
class LinpackResults(pydantic.BaseModel):
        ht_config: str = pydantic.Field(description="hyperthread config")
        sockets: int = pydantic.Field(description="How many sockets being used.", gt=0)
        threads: int = pydantic.Field(description="How many threads we ran", gt=0)
        unit: str = pydantic.Field(description="unit of the results")
        results: int = pydantic.Field(description="Reported linpack results", gt=0)
        cpu_affin: str = pydantic.Field(description="Affinity of the cpus")
