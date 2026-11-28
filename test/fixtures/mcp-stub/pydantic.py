class BaseModel:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


def Field(default=None, **kwargs):
    return default
