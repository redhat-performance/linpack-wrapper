import pydantic
import datetime


class Linpack_Results(pydantic.BaseModel):
    ht_config: str
    sockets: int = pydantic.Field(gt=0)
    threads: int = pydantic.Field(gt=0)
    unit: str
    MB_per_sec: int = pydantic.Field(gt=0)
    cpu_affin: str
    Start_Date: datetime.datetime
    End_Date: datetime.datetime

